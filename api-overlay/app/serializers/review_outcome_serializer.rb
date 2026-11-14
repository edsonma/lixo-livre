# What the moderator's app gets back after approving or rejecting a report.
class ReviewOutcomeSerializer < ApplicationSerializer
  def as_json(*)
    { id: record.id, ai_status: record.ai_status, published: record.published?, hidden: record.hidden_at.present? }
  end
end
