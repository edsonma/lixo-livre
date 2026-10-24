module Api
  module V1
    class FlagsController < BaseController
      before_action :require_device!

      # POST /api/v1/trashes/:trash_id/flags   { reason: "privacy" }
      def create
        trash = Trash.find(params[:trash_id])
        flag = trash.flags.create!(device: @device, reason: params.require(:reason))
        render json: { id: flag.id }, status: :created
      end
    end
  end
end
