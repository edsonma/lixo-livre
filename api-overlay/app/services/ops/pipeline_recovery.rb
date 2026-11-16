# Reports that were uploaded but never finished the pipeline (the server restarted while jobs were
# queued in memory, or a job gave up) get put back in line. Safe to run any number of times.
module Ops::PipelineRecovery
  # Returns how many reports were re-queued for each step.
  def self.requeue_stuck(older_than: 10.minutes, now: Time.current)
    stuck = Trash.pending.where("created_at < ?", now - older_than)

    unsanitized = stuck.where(sanitized_at: nil).pluck(:id)
    unvalidated = stuck.where.not(sanitized_at: nil).pluck(:id)

    unsanitized.each { |id| SanitizePhotoJob.perform_later(id) }
    unvalidated.each { |id| ValidateTrashJob.perform_later(id) }

    { sanitize: unsanitized.size, validate: unvalidated.size }
  end

  # Reports that were scored but never published (the author closed the page) are private and
  # useless after a while: delete them. Returns how many were removed.
  def self.purge_stale_drafts(older_than: 7.days, now: Time.current)
    stale = Trash.drafts.where("validated_at < ?", now - older_than).to_a
    stale.each(&:destroy)
    stale.size
  end

  # Photos the AI found no trash in: the file is already gone; this removes the report itself, a day later
  # (the author's screen has read the answer by then). Also clears the ones rejected before this rule existed.
  # Returns how many were removed.
  def self.purge_no_trash(older_than: 1.day, now: Time.current)
    stale = Trash.no_trash_found.where("updated_at < ?", now - older_than).to_a
    stale.each(&:destroy)
    stale.size
  end
end
