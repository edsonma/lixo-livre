module Api
  module V1
    # The places the logged-in person follows. A cell the person follows can send notifications.
    class FollowsController < BaseController
      before_action :require_login!

      # GET /api/v1/follows
      def index
        follows = current_user.follows.order(created_at: :desc).to_a

        render json: FollowSerializer.collection(follows, cells: HeatCell.by_h3(follows.map(&:h3_index)))
      end

      # POST /api/v1/follows  { h3_index }   (following twice is fine)
      def create
        h3 = params.require(:h3_index).to_s
        raise ActiveRecord::RecordNotFound unless h3.match?(Follow::H3_FORMAT) && Trash.for_heatmap.exists?(h3_index: h3)

        follow = Follow.start(current_user, h3)
        render json: FollowSerializer.call(follow, cells: HeatCell.by_h3([h3])), status: :created
      end

      # DELETE /api/v1/follows/:h3_index
      def destroy
        current_user.follows.find_by!(h3_index: params[:h3_index].to_s).destroy!
        head :no_content
      end
    end
  end
end
