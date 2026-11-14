class NotificationSerializer < ApplicationSerializer
  def as_json(*)
    {
      id: record.id, kind: record.kind, h3: record.h3_index,
      score: record.score&.round(1), previous_score: record.previous_score&.round(1),
      lat: record.lat, lng: record.lng, read: record.read_at.present?, created_at: record.created_at
    }
  end
end
