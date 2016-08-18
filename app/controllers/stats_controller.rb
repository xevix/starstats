class StatsController < ApplicationController
  def index
    @star_view = starred_per_month
    @user = user
  end

  def stars_received
    @star_views = fetch_stars_received
    @user = user
  end

  private
  def starred_per_month
    stats_service.starred_per_month_by_user(user)
  end

  def fetch_stars_received
    stats_service.stars_received_for_user_per_repo(user)
  end

  def user
    params[:user] || ENV["github_user"]
  end

  def stats_service
    StatsService.instance
  end
end
