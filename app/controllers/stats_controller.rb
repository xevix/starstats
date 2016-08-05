class StatsController < ApplicationController
  def index
    @star_view = starred_per_month
  end

  private
  def starred_per_month
    stats_service.starred_per_month
  end

  def stats_service
    StatsService.instance
  end
end
