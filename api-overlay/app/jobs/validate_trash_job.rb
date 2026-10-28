class ValidateTrashJob < ApplicationJob
  queue_as :default

  CONFIDENCE_THRESHOLD = 0.6
  # A cleanup erases the reports made before it, so the AI has to be surer, and the photo has to show
  # (almost) nothing: a clean place, or at most a couple of items.
  CLEANUP_CONFIDENCE = 0.8
  CLEANED_MAX_SEVERITY = 15

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

    return validate_cleanup(trash) if trash.cleanup?

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
        validated_at: Time.current,
        published_at: (Time.current if Trash.auto_publish?)
      )
    end
  end

  private

  # "Já foi limpo": the photo has to show a clean place, where something had been reported.
  def validate_cleanup(trash)
    unless trash.dirty_reports_nearby?
      trash.update!(ai_status: :rejected, ai_payload: { "reason" => "nothing_to_clean" })
      return
    end

    result = TrashVision.analyze(trash.photo)
    raw = (result.raw || {}).to_h

    if result.is_trash && result.severity.to_i > CLEANED_MAX_SEVERITY
      trash.update!(ai_status: :rejected, ai_payload: raw.merge("reason" => "still_dirty"))
    elsif result.confidence < CLEANUP_CONFIDENCE
      trash.update!(ai_status: :needs_review, ai_confidence: result.confidence, ai_payload: raw)
    else
      trash.update!(
        ai_status: :validated, severity: result.is_trash ? result.severity : 0, trash_types: [],
        ai_confidence: result.confidence, ai_payload: raw, validated_at: Time.current,
        published_at: (Time.current if Trash.auto_publish?)
      )
    end
  end
end
