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
            held: ReviewSerializer.collection(held.includes(:user, :flags).with_attached_photo.limit(LIMIT), urls: self, kind: "held"),
            flagged: ReviewSerializer.collection(flagged.includes(:user, :flags).with_attached_photo.limit(LIMIT), urls: self, kind: "flagged")
          }
        end

        def approve
          trash = Trash.find(params[:id])
          if trash.needs_review?
            severity = Integer(params.require(:severity).to_s, exception: false)
            return render(json: { errors: { severity: ["must be a number from 0 to 100"] } }, status: :unprocessable_entity) unless severity

            trash.approve_after_review!(severity: severity, types: review_types, reviewer: current_user)
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

        # nil keeps what the AI found; anything else replaces it (and is checked against the known types by the model)
        def review_types
          Array.wrap(params[:trash_types]).map(&:to_s) unless params[:trash_types].nil?
        end
      end
    end
  end
end
