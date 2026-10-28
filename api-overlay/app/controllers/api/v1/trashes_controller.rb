module Api
  module V1
    class TrashesController < BaseController
      before_action :require_login!, only: :create
      before_action :require_device!, only: :create

      # GET /api/v1/trashes?lat=&lng=&radius=   (photos near a clicked hotspot)
      def index
        radius = params.fetch(:radius, 100).to_f.clamp(10, 500)

        trashes = Trash.for_heatmap
                       .near(params.require(:lng), params.require(:lat), radius)
                       .includes(:user).with_attached_photo
                       .order(taken_at: :desc).limit(30)

        render json: trashes.map { |t| serialize_trash(t) }
      end

      def show
        render json: serialize_trash(Trash.for_heatmap.find(params[:id]))
      end

      # POST /api/v1/trashes   multipart: photo, lat, lng, taken_at, extra_info, kind ("dirty", or "cleanup" for "Já foi limpo")
      def create
        trash = @device.trashes.new(
          user: current_user,
          lonlat: Trash.point(params.require(:lng), params.require(:lat)),
          taken_at: params.require(:taken_at),
          extra_info: params[:extra_info],
          kind: params[:kind].presence || "dirty",
          photo: params[:photo]
        )
        trash.save!

        # The AI scores it asynchronously; the app polls /me/trashes for the result.
        render json: { id: trash.id, ai_status: trash.ai_status }, status: :accepted
      end
    end
  end
end
