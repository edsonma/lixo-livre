module Api
  module V1
    class FlagsController < BaseController
      before_action :require_device!

      # two requests from the same device at once: the unique index catches the second
      rescue_from ActiveRecord::RecordNotUnique do
        render json: { errors: { device_id: ["has already been taken"] } }, status: :unprocessable_entity
      end

      # POST /api/v1/trashes/:trash_id/flags   { reason: "privacy" }
      def create
        trash = Trash.for_heatmap.find(params[:trash_id]) # only photos that are publicly visible
        flag = trash.flags.create!(device: @device, reason: params.require(:reason))
        render json: { id: flag.id }, status: :created
      end
    end
  end
end
