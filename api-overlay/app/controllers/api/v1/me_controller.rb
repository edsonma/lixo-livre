module Api
  module V1
    class MeController < BaseController
      before_action :require_device!

      # GET /api/v1/me/trashes   the "my pictures" feed in the mobile app (all statuses)
      # photo_url is only given once the photo has been sanitized (faces and
      # plates blurred), so the app never displays or links the raw original.
      def trashes
        trashes = @device.trashes.with_attached_photo.order(taken_at: :desc).limit(50)

        render json: trashes.map { |t| serialize_own_trash(t) }
      end

      # GET /api/v1/me/trashes/:id   poll one report after uploading it:
      # stage goes protecting_photo -> analyzing -> scored | not_trash | in_review, and done flips to true.
      def show
        render json: serialize_own_trash(@device.trashes.with_attached_photo.find(params[:id]))
      end

      private

      def serialize_own_trash(trash)
        ready = trash.sanitized_at.present?
        {
          id: trash.id,
          ai_status: trash.ai_status,
          stage: stage_of(trash),
          done: !trash.pending?,
          severity: trash.severity,
          trash_types: trash.trash_types,
          taken_at: trash.taken_at,
          photo_ready: ready,
          photo_url: ready ? url_for(trash.photo) : nil
        }
      end

      def stage_of(trash)
        case trash.ai_status
        when "validated" then "scored"
        when "rejected" then "not_trash"
        when "needs_review" then "in_review"
        else trash.sanitized_at ? "analyzing" : "protecting_photo"
        end
      end
    end
  end
end
