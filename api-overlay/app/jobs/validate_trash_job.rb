class ValidateTrashJob < ApplicationJob
  queue_as :default

  CONFIDENCE_THRESHOLD = 0.6

  retry_on StandardError, wait: :polynomially_longer, attempts: 5 do |job, error|
    Trash.find_by(id: job.arguments.first)&.hold_for_review!("validation_failed: #{error.class}")
  end
  discard_on ActiveRecord::RecordNotFound

  def perform(trash_id)
    trash = Trash.find(trash_id)
    return unless trash.pending?
    return unless trash.sanitized_at # never analyze or publish a photo that has not been sanitized

    if trash.metadata_suspicious?
      # The photo claims to be from far away or long ago: a human decides, no AI spend.
      trash.update!(ai_status: :needs_review, ai_payload: { "reason" => "metadata_mismatch" })
      return
    end

    result = TrashVision.analyze(trash.photo)

    if !result.is_trash
      trash.update!(ai_status: :rejected, ai_payload: result.raw)
    elsif result.confidence < CONFIDENCE_THRESHOLD
      trash.update!(ai_status: :needs_review, ai_confidence: result.confidence, ai_payload: result.raw)
    else
      trash.update!(
        ai_status: :validated,
        severity: result.severity,
        trash_types: result.types,
        ai_confidence: result.confidence,
        ai_payload: result.raw,
        validated_at: Time.current
      )
    end
  end
end
