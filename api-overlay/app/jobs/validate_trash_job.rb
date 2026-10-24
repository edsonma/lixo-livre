class ValidateTrashJob < ApplicationJob
  queue_as :default
  retry_on StandardError, wait: :polynomially_longer, attempts: 5

  CONFIDENCE_THRESHOLD = 0.6

  def perform(trash_id)
    trash = Trash.find(trash_id)
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
