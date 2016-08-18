class StatsController < ApplicationController
  def index
    @star_view = starred_per_month
    @user = user
  end

  private
  def starred_per_month
    stats_service.starred_per_month_by_user(user)
  end

  def user
    params[:user] || ENV["github_user"]
  end

  def stats_service
    StatsService.instance
  end
end
