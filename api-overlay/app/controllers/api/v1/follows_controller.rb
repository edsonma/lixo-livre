module Api
  module V1
    # The places the logged-in person follows. A cell the person follows can send notifications.
    class FollowsController < BaseController
      before_action :require_login!

      # GET /api/v1/follows
      def index
        render json: current_user.follows.order(created_at: :desc).map { |f| serialize(f) }
      end

      # POST /api/v1/follows  { h3_index }   (following twice is fine)
      def create
        h3 = params.require(:h3_index).to_s
        raise ActiveRecord::RecordNotFound unless h3.match?(Follow::H3_FORMAT) && Trash.for_heatmap.exists?(h3_index: h3)

        follow = Follow.start(current_user, h3)
        render json: serialize(follow), status: :created
      end

      # DELETE /api/v1/follows/:h3_index
      def destroy
        current_user.follows.find_by!(h3_index: params[:h3_index].to_s).destroy!
        head :no_content
      end

      private

      def serialize(follow)
        cell = HeatCell.find_by(h3_index: follow.h3_index, resolution: Trash::H3_RESOLUTION)
        { h3: follow.h3_index, score: cell&.score&.round(1), lat: cell&.lonlat&.y, lng: cell&.lonlat&.x, since: follow.created_at }
      end
    end
  end
end
