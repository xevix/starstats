class StatsService
  include Singleton

  STARRED_KEY = "my:starred"

  # [[year, [month, count], [month, count]]]
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
    # TODO: Do the full list, not just the first page
    # TODO: unhardcode username
    if latest_starred_redis.nil?
      # Grab the latest from the API
      starred_api = $octokit.starred("xevix", accept: 'application/vnd.github.v3.star+json', sort: "created", direction: "desc")
      starred_api.each do |starred_entry|
        $redis.rpush STARRED_KEY, starred_entry.to_attrs.to_json
      end
    end

    # Fetch from cache and return
    $redis.lrange(STARRED_KEY, 0, -1).collect { |e| JSON.parse(e) }
  end
end