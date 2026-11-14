# A moderator's decision on a report in the queue (see ModerationQueue). The same two words mean two things:
#
#   held report      approve: it gets the severity the moderator chose and goes to the map
#                    reject:  it is rejected and its photo deleted
#   flagged report   approve: the photo stays (the flags are dismissed)
#                    reject:  the photo is taken down (the flags are resolved)
#
# Raises Trash::NotReviewable when the report is in neither queue. For a held report, approve needs a severity:
# SeverityMissing when none was sent, SeverityInvalid when it is not a whole number (the model checks 0-100).
class ReviewReport
  class SeverityMissing < StandardError; end
  class SeverityInvalid < StandardError; end

  def initialize(trash, reviewer:)
    @trash = trash
    @reviewer = reviewer
  end

  # types: nil keeps what the AI found; an array replaces it.
  def approve(severity: nil, types: nil)
    return keep_flagged_photo unless @trash.needs_review?

    @trash.approve_after_review!(severity: whole_number(severity), types: types, reviewer: @reviewer)
    @trash
  end

  def reject
    if @trash.needs_review?
      @trash.reject_after_review!(reviewer: @reviewer)
    else
      require_pending_flags!
      @trash.take_down_after_flags!
    end
    @trash
  end

  private

  def keep_flagged_photo
    require_pending_flags!
    @trash.keep_after_flags!
    @trash
  end

  def require_pending_flags!
    raise Trash::NotReviewable, "report #{@trash.id} has no pending reports" unless @trash.flags.pending.exists?
  end

  def whole_number(severity)
    raise SeverityMissing if severity.blank?

    Integer(severity.to_s, exception: false) or raise SeverityInvalid
  end
end
