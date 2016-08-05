class StatsService
  include Singleton

  STARRED_KEY = "my:starred"
  GITHUB_USER = ENV["github_user"]

  # TODO: reorganize results so view needs no logic for displaying
  # [year, [[month, count], [month, count]]]
  def starred_per_month
    starred = fetch_starred
    starred_by_month = {}
    starred.each do |star|
      datetime = DateTime.parse(star["starred_at"])
      year = datetime.year
      month = datetime.month
      this_year = starred_by_month[year] || {}
      this_month = this_year[month] || 0
      this_year[month] = this_month + 1
      starred_by_month[year] = this_year
    end

    starred_by_month.keys.sort.collect do |year|
      [year, (1..12).to_a.collect { |month| [month, starred_by_month[year][month] || 0] } ]
    end
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