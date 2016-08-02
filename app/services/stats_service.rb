class StatsService
  include Singleton

  def starred_per_month
    stars = $octokit.starred("xevix", :accept => 'application/vnd.github.v3.star+json')
    stars
  end
end