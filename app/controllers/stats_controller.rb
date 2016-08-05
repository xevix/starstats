class StatsController < ApplicationController
  def index
    @star_view = starred_per_month
    @user = user
  end

  private
  def starred_per_month
    stats_service.starred_per_month(user)
  end

  def user
    params[:user]
  end

  def stats_service
    StatsService.instance
  end
end
