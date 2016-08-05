class StatsService
  include Singleton

  STARRED_KEY = "my:starred"
  GITHUB_USER = ENV["github_user"]

  def starred_per_month
    starred = fetch_starred
    starred_by_month = {}
    total_stars = 0
    year_stars = {}
    month_stars = {}

    starred.each do |star|
      datetime = DateTime.parse(star["starred_at"])
      year = datetime.year
      month = datetime.month

      this_year = starred_by_month[year] || {}
      this_month = this_year[month] || 0
      this_year[month] = this_month + 1
      starred_by_month[year] = this_year

      total_stars += 1
      if year_stars[year]
        year_stars[year] += 1
      else
        year_stars[year] = 1
      end

      if month_stars[month]
        month_stars[month] += 1
      else
        month_stars[month] = 1
      end
    end


    years = starred_by_month.keys.sort

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

  def fetch_starred
    # Grab the latest from Redis
    latest_starred_redis_maybe = $redis.lindex STARRED_KEY, 0
    latest_starred_redis =
        if latest_starred_redis_maybe.present?
          JSON.parse(latest_starred_redis_maybe)
        end

    # If results are missing, cache them
    # TODO: Proper check from the API periodically for new data
    # TODO: allow setting of user via variable
    if latest_starred_redis.nil?
      # Grab the latest from the API
      $octokit.starred(GITHUB_USER, accept: 'application/vnd.github.v3.star+json', sort: "created", direction: "desc", per_page: 100)

      # Store response for pagination links
      latest_api_response = $octokit.last_response

      # Loop until there's no next page
      while true do
        latest_api_response.data.each do |starred_entry|
          $redis.rpush STARRED_KEY, starred_entry.to_attrs.to_json
        end

        break unless latest_api_response.rels[:next]

        latest_api_response = latest_api_response.rels[:next].call({sort: "created", direction: "desc", per_page: 100}, {method: :get, headers: {accept: 'application/vnd.github.v3.star+json'}})
      end
    end

    # Fetch from cache and return
    $redis.lrange(STARRED_KEY, 0, -1).collect { |e| JSON.parse(e) }
  end

end