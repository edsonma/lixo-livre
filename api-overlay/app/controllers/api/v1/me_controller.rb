module Api
  module V1
    class MeController < BaseController
      before_action :require_device!

      # GET /api/v1/me/trashes   the "my pictures" feed in the mobile app (all statuses)
      def trashes
        trashes = @device.trashes.with_attached_photo.order(taken_at: :desc).limit(50)

        render json: trashes.map { |t|
          {
            id: t.id,
            ai_status: t.ai_status,
            severity: t.severity,
            trash_types: t.trash_types,
            taken_at: t.taken_at,
            photo_url: url_for(t.photo)
          }
        }
      end
    end
  end
end
