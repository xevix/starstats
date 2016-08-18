class StatsService
  include Singleton

  ACCEPT_HEADER = "application/vnd.github.v3.star+json"
  DEFAULT_GITHUB_USER = ENV["github_user"]
  PER_PAGE = 100
  SORT = "created"
  DIRECTION = "desc"
  STARRED_KEY = "my:starred"

  def starred_per_month(user)
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

    # Fetch the starred repos of this user
    starred = fetch_starred(user)

    # Iterate over all starred repos
    starred.each do |star|
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
                year_star_totals: years.collect { |year| year_stars[year] },
                month_star_totals: (1..12).to_a.collect { |month| month_stars[month] }
            }
    }
  end

  def fetch_starred(user)
    user ||= DEFAULT_GITHUB_USER
    # Grab the latest from Redis
    latest_starred_redis_maybe = $redis.lindex(starred_key(user), 0)
    latest_starred_redis =
        if latest_starred_redis_maybe.present?
          JSON.parse(latest_starred_redis_maybe)
        end

    # If results are missing, cache them
    # TODO: Proper check from the API periodically for new data
    if latest_starred_redis.nil?
      # Grab the latest from the API
      $octokit.starred(user, accept: ACCEPT_HEADER, sort: SORT, direction: DIRECTION, per_page: PER_PAGE)

      # Store response for pagination links
      latest_api_response = $octokit.last_response

      # Loop until there's no next page
      while true do
        latest_api_response.data.each do |starred_entry|
          $redis.rpush starred_key(user), starred_entry.to_attrs.to_json
        end

        break unless latest_api_response.rels[:next]

        latest_api_response = latest_api_response.rels[:next].call({sort: SORT, direction: DIRECTION, per_page: PER_PAGE}, {method: :get, headers: {accept: ACCEPT_HEADER}})
      end
    end

    # Fetch from cache and return
    $redis.lrange(starred_key(user), 0, -1).collect { |e| JSON.parse(e) }
  end

  private
  def starred_key(user)
    STARRED_KEY + ":" + user
  end

end