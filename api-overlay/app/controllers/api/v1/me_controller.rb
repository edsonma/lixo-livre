module Api
  module V1
    class MeController < BaseController
      before_action :require_device!

      # GET /api/v1/me/trashes   the "my pictures" feed in the mobile app (all statuses)
      # photo_url is only given once the photo has been sanitized (metadata stripped, faces and
      # plates blurred), so the app never displays or links the raw original.
      def trashes
        trashes = @device.trashes.with_attached_photo.order(taken_at: :desc).limit(50)

        render json: trashes.map { |t|
          ready = t.sanitized_at.present?
          {
            id: t.id,
            ai_status: t.ai_status,
            severity: t.severity,
            trash_types: t.trash_types,
            taken_at: t.taken_at,
            photo_ready: ready,
            photo_url: ready ? url_for(t.photo) : nil
          }
        }
      end
    end
  end
end
