class PasskeySerializer < ApplicationSerializer
  def as_json(*)
    { id: record.id, nickname: record.nickname, created_at: record.created_at, last_used_at: record.last_used_at }
  end
end
