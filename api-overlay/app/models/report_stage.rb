# Where a report is in its life, in the words the app uses (the author polls it after uploading):
#
#   protecting_photo -> analyzing -> scored | published | not_trash | still_dirty | nothing_to_clean | in_review
#
# "scored" waits for the author: publishing puts it on the map ("published"), discarding throws it away.
module ReportStage
  # A cleanup can be turned down for its own reasons; anything else rejected is "not trash".
  CLEANUP_REJECTIONS = %w[still_dirty nothing_to_clean].freeze

  def self.of(trash)
    case trash.ai_status
    when "validated" then trash.published? ? "published" : "scored"
    when "rejected" then rejection(trash)
    when "needs_review" then "in_review"
    else trash.sanitized_at ? "analyzing" : "protecting_photo"
    end
  end

  def self.rejection(trash)
    reason = (trash.ai_payload || {})["reason"]
    CLEANUP_REJECTIONS.include?(reason) ? reason : "not_trash"
  end
  private_class_method :rejection
end
