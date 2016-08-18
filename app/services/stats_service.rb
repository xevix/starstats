class StatsService
  include Singleton

  ACCEPT_HEADER = "application/vnd.github.v3.star+json"
  DEFAULT_GITHUB_USER = ENV["github_user"]
  PER_PAGE = 100
  SORT = "created"
  DIRECTION = "desc"
  STARRED_KEY = "my:starred"
  STARRED_FOR_KEY = "my:repos"
  STARGAZERS_KEY = "my:repos:stargazers"

  def starred_per_month_by_user(user)
    # Fetch the starred repos of this user
    stars = fetch_starred_by_user(user)
    star_stats_from_stars(stars)
  end

  def stars_received_for_user_per_repo(user)
    stargazed_repos = fetch_stars_for_user_per_repo(user)

    stargazed_repos.collect do |repo|
      stars = repo[:stargazers]
      {
          repo_name: repo[:repo_name],
          repo_stars: star_stats_from_stars(stars)
      }
    end.sort do |a, b|
      b[:repo_stars][:total_stars] <=> a[:repo_stars][:total_stars]
    end
  end

  private
  def star_stats_from_stars(stars)
    ## Data aggregators

    # key: year, month; value: total stars of year-month, e.g. 2016 January
    starred_by_month = {}
    # Overall total number of repos starred
    total_stars = 0
    # key: year; value: number of repos starred that year
    year_stars = {}
    # key: month; value: number of repos starred that month over all years
    month_stars = {}

    ## Data processing

    # Iterate over all starred repos
    stars.each do |star|
      datetime = DateTime.parse(star["starred_at"])
      year = datetime.year
      month = datetime.month

      # Fetch number of stars for the given year or initialize to empty hash
      this_year = starred_by_month[year] || {}
      # Fetch number of stars for this year-month, or initialize to 0
      this_month = this_year[month] || 0
      # Count the current star in the count for this year-month
      this_year[month] = this_month + 1
      # Update the year-month hash with the new star count
      starred_by_month[year] = this_year

      # Count the current star in the total star count
      total_stars += 1
      # Count the star for this year, adding 1 to the total count or initializing it to 1
      if year_stars[year]
        year_stars[year] += 1
      else
        year_stars[year] = 1
      end

      # Count the star for this month, adding 1 to the total count or initializing it to 1
      if month_stars[month]
        month_stars[month] += 1
      else
        month_stars[month] = 1
      end
    end

    # Collect all years for which there are stars, sorted by year
    years = starred_by_month.keys.sort

    # Generate the final data
    {
        total_stars: total_stars,
        stars:
            {
                years: years,
                month_stars: (1..12).to_a.collect { |month| years.collect { |year| starred_by_month[year][month] || 0 } },
                year_star_totals: years.empty? ? [0] : years.collect { |year| year_stars[year] },
                month_star_totals: (1..12).to_a.collect { |month| month_stars[month] || 0 }
            }
    }
  end

  def fetch_stars_for_user_per_repo(user)
    user = fetch_user(user)
    # Return value. e.g. [{repo_name: "user/myrepo", stargazers: [...{"starred_at" => "2016-06-15T19:04:38.000Z"}...]}]
    repo_stars = []

    # Fetch repo names from Redis
    repo_names = fetch_user_repos(user).collect { |r| r["full_name"] }

    # Fetch stars per repo
    repo_names.each do |repo_name|
      stargazers_key = repo_stargazers_key(user, repo_name)

      latest_stargazers_redis = fetch_head_by_key(stargazers_key)
      if latest_stargazers_redis.nil?
        # TODO: pagination
        stargazers = $octokit.stargazers(repo_name, accept: ACCEPT_HEADER, sort: SORT, direction: DIRECTION, per_page: PER_PAGE)
        store_list_by_key(stargazers_key, stargazers)
      end

      # Fetch stargazers from Redis
      gazers = fetch_list_by_key(stargazers_key)
      # Add to output list
      repo_stars << {repo_name: repo_name, stargazers: gazers}
    end

    repo_stars
  end

  def fetch_user_repos(user)
    user = fetch_user(user)
    starred_key = starred_for_user_key(user)

    # Grab latest from Redis
    latest_repos_redis = fetch_head_by_key(starred_key)

    if latest_repos_redis.nil?
      # Fetch all repositories that are not a fork
      # TODO: handle pagination
      repos = $octokit.repositories(user, type: "owner").select { |r| !r.fork }
      # Store in Redis
      store_list_by_key(starred_key, repos)
    end

    # Fetch repo ids from Redis
    fetch_list_by_key(starred_for_user_key(user))
  end

  def fetch_starred_by_user(user)
    user = fetch_user(user)
    key = starred_by_user_key(user)

    # Grab the latest from Redis
    latest_starred_redis = fetch_head_by_key(key)
    # If results are missing, cache them
    # TODO: Proper check from the API periodically for new data
    if latest_starred_redis.nil?
      # Grab the latest from the API
      $octokit.starred(user, accept: ACCEPT_HEADER, sort: SORT, direction: DIRECTION, per_page: PER_PAGE)

      # Store response for pagination links
      latest_api_response = $octokit.last_response

      # Loop until there's no next page
      while true do
        store_list_by_key(key, latest_api_response.data)

        if latest_api_response.rels[:next]
          latest_api_response = latest_api_response.rels[:next].call({sort: SORT, direction: DIRECTION, per_page: PER_PAGE}, {method: :get, headers: {accept: ACCEPT_HEADER}})
        else
          break
        end
      end
    end

    # Fetch from cache and return
    fetch_list_by_key(key)
  end

  ## Redis

  def fetch_list_by_key(key)
    $redis.lrange(key, 0, -1).collect { |e| JSON.parse(e) }
  end

  def store_list_by_key(key, list)
    list.each { |r| $redis.rpush key, r.to_attrs.to_json }
  end

  def fetch_head_by_key(key)
    latest_maybe = $redis.lindex(key, 0)
    if latest_maybe.present?
      JSON.parse(latest_maybe)
    end
  end

  def starred_by_user_key(user)
    STARRED_KEY + ":" + user
  end

  def starred_for_user_key(user)
    STARRED_FOR_KEY + ":" + user
  end

  def repo_stargazers_key(user, repo_name)
    STARGAZERS_KEY + ":" + user + ":" + repo_name
  end

  def fetch_user(user)
    user || DEFAULT_GITHUB_USER
  end

end