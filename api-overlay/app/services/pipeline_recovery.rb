# Reports that were uploaded but never finished the pipeline (the server restarted while jobs were
# queued in memory, or a job gave up) get put back in line. Safe to run any number of times.
module PipelineRecovery
  # Returns how many reports were re-queued for each step.
  def self.requeue_stuck(older_than: 10.minutes, now: Time.current)
    stuck = Trash.pending.where("created_at < ?", now - older_than)

    unsanitized = stuck.where(sanitized_at: nil).pluck(:id)
    unvalidated = stuck.where.not(sanitized_at: nil).pluck(:id)

    unsanitized.each { |id| SanitizePhotoJob.perform_later(id) }
    unvalidated.each { |id| ValidateTrashJob.perform_later(id) }

    { sanitize: unsanitized.size, validate: unvalidated.size }
  end
end
