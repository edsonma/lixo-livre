module Api
  module V1
    class FlagsController < BaseController
      before_action :require_device!

      # POST /api/v1/trashes/:trash_id/flags   { reason: "privacy" }
      def create
        trash = Trash.for_heatmap.find(params[:trash_id]) # only photos that are publicly visible
        flag = trash.flags.create!(device: @device, reason: params.require(:reason))
        render json: { id: flag.id }, status: :created
      end
    end
  end
end
