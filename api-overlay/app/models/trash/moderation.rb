# What admins and moderators can do to a report. Two queues, see Api::V1::Admin::ReviewsController:
# held reports (the pipeline would not publish them by itself) and published photos people flagged.
module Trash::Moderation
  extend ActiveSupport::Concern

  class NotReviewable < StandardError; end

  # Used when the pipeline cannot finish: keeps the report private until a human looks at it.
  def hold_for_review!(reason)
    update_columns(
      ai_status: "needs_review",
      ai_payload: (ai_payload || {}).merge("hold_reason" => reason),
      updated_at: Time.current
    )
  end

  # --- held reports ---

  # A person looked at the protected photo and decided the severity. It goes to the map right away.
  # A photo that was never sanitized cannot be approved.
  def approve_after_review!(severity:, types: nil, reviewer: nil)
    raise NotReviewable, "report #{id} is not waiting for review" unless needs_review?
    raise NotReviewable, "report #{id} has no protected photo yet" unless sanitized_at.present?

    update!(
      ai_status: :validated, severity: severity, trash_types: types.nil? ? trash_types : types,
      validated_at: Time.current, published_at: Time.current,
      ai_payload: (ai_payload || {}).merge("reviewed" => "approved", "reviewer_id" => reviewer&.id)
    )
  end

  def reject_after_review!(reviewer: nil)
    raise NotReviewable, "report #{id} is not waiting for review" unless needs_review?

    update_columns(ai_status: "rejected", updated_at: Time.current,
                   ai_payload: (ai_payload || {}).merge("reviewed" => "rejected", "reviewer_id" => reviewer&.id))
    photo.purge_later
  end

  # --- flagged photos: a published photo people reported ---

  # The moderator says it is fine ...
  def keep_after_flags!
    transaction do
      flags.pending.update_all(status: "dismissed")
      update!(hidden_at: nil)
    end
  end

  # ... or takes it down.
  def take_down_after_flags!
    transaction do
      flags.pending.update_all(status: "resolved")
      update!(hidden_at: hidden_at || Time.current)
    end
    photo.purge_later # a photo's address keeps working after it leaves the map unless the file is deleted
  end
end
