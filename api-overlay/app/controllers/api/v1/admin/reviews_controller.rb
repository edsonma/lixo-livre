module Api
  module V1
    module Admin
      # The moderation queue, for admins and moderators.
      #   held     reports the pipeline would not publish by itself (photo taken far away, AI unsure, a failure)
      #   flagged  published photos that people reported
      #
      #   GET  /api/v1/admin/reviews
      #   POST /api/v1/admin/reviews/:id/approve   held: { severity: 0-100, trash_types: [...] } publishes it; flagged: keeps it
      #   POST /api/v1/admin/reviews/:id/reject    held: rejects it and deletes the photo; flagged: takes it down
      class ReviewsController < BaseController
        before_action :require_moderator!

        LIMIT = 50

        def index
          held = Trash.needs_review.order(created_at: :desc)
          flagged = Trash.where(id: Flag.pending.select(:trash_id)).order(updated_at: :desc)

          render json: {
            counts: { held: held.count, flagged: flagged.count },
            held: held.includes(:user, :flags).with_attached_photo.limit(LIMIT).map { |t| serialize_review(t, "held") },
            flagged: flagged.includes(:user, :flags).with_attached_photo.limit(LIMIT).map { |t| serialize_review(t, "flagged") }
          }
        end

        def approve
          trash = Trash.find(params[:id])
          if trash.needs_review?
            severity = Integer(params.require(:severity).to_s, exception: false)
            return render(json: { errors: { severity: ["must be a number from 0 to 100"] } }, status: :unprocessable_entity) unless severity

            trash.approve_after_review!(severity: severity, types: params[:trash_types]&.map(&:to_s), reviewer: current_user)
          else
            raise Trash::NotReviewable, "report #{trash.id} has no pending reports" unless trash.flags.pending.exists?

            trash.keep_after_flags!
          end
          render json: { id: trash.id, ai_status: trash.ai_status, published: trash.published?, hidden: trash.hidden_at.present? }
        end

        def reject
          trash = Trash.find(params[:id])
          if trash.needs_review?
            trash.reject_after_review!(reviewer: current_user)
          else
            raise Trash::NotReviewable, "report #{trash.id} has no pending reports" unless trash.flags.pending.exists?

            trash.take_down_after_flags!
          end
          render json: { id: trash.id, ai_status: trash.ai_status, published: trash.published?, hidden: trash.hidden_at.present? }
        end

        rescue_from Trash::NotReviewable do |e|
          render json: { error: "not_reviewable", message: e.message }, status: :unprocessable_entity
        end

        private

        # An un-protected photo (privacy step did not finish) is never shown, even to admins.
        def serialize_review(trash, kind)
          protected_photo = trash.sanitized_at.present?
          meta = trash.photo_meta || {}
          payload = trash.ai_payload || {}
          {
            id: trash.id,
            kind: kind,
            reason: review_reason(trash, kind),
            flags: trash.flags.map(&:reason).tally,
            severity: trash.severity,
            trash_types: trash.trash_types,
            ai_confidence: trash.ai_confidence,
            extra_info: trash.extra_info,
            taken_at: trash.taken_at,
            created_at: trash.created_at,
            lat: trash.lonlat.y,
            lng: trash.lonlat.x,
            exif_distance_m: meta["exif_distance_m"],
            hold_reason: payload["hold_reason"],
            uploader: trash.user && { id: trash.user_id, name: trash.user.name, email: trash.user.email },
            hidden: trash.hidden_at.present?,
            photo_protected: protected_photo,
            photo_url: protected_photo && trash.photo.attached? ? url_for(trash.photo) : nil
          }
        end

        def review_reason(trash, kind)
          return "flagged" if kind == "flagged"

          payload = trash.ai_payload || {}
          return payload["reason"] if payload["reason"].present?
          return "failed" if payload["hold_reason"].present?

          trash.ai_confidence ? "low_confidence" : "other"
        end
      end
    end
  end
end
