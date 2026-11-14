module Api
  module V1
    module Admin
      # The moderation queue, for admins and moderators (ModerationQueue says what is in it, ReviewReport
      # what approving and rejecting mean for each kind).
      #
      #   GET  /api/v1/admin/reviews
      #   POST /api/v1/admin/reviews/:id/approve   held: { severity: 0-100, trash_types: [...] } publishes it; flagged: keeps it
      #   POST /api/v1/admin/reviews/:id/reject    held: rejects it and deletes the photo; flagged: takes it down
      class ReviewsController < BaseController
        before_action :require_moderator!

        LIMIT = 50

        rescue_from Trash::NotReviewable do |e|
          render json: { error: "not_reviewable", message: e.message }, status: :unprocessable_entity
        end
        rescue_from ReviewReport::SeverityMissing do
          render json: { errors: { severity: ["is required"] } }, status: :bad_request
        end
        rescue_from ReviewReport::SeverityInvalid do
          render json: { errors: { severity: ["must be a number from 0 to 100"] } }, status: :unprocessable_entity
        end

        def index
          queue = ModerationQueue.new

          render json: {
            counts: { held: queue.held.count, flagged: queue.flagged.count },
            held: listing(queue.held, "held"),
            flagged: listing(queue.flagged, "flagged")
          }
        end

        def approve
          trash = ReviewReport.new(Trash.find(params[:id]), reviewer: current_user)
                              .approve(severity: params[:severity], types: review_types)
          render json: ReviewOutcomeSerializer.call(trash)
        end

        def reject
          trash = ReviewReport.new(Trash.find(params[:id]), reviewer: current_user).reject
          render json: ReviewOutcomeSerializer.call(trash)
        end

        private

        def listing(trashes, kind)
          ReviewSerializer.collection(trashes.includes(:user, :flags).with_attached_photo.limit(LIMIT), urls: self, kind: kind)
        end

        # nil keeps what the AI found; anything else replaces it (and is checked against the known types by the model)
        def review_types
          Array.wrap(params[:trash_types]).map(&:to_s) unless params[:trash_types].nil?
        end
      end
    end
  end
end
