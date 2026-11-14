# A report as its author sees it, whatever its status. photo_url and thumb_url are only given once the
# photo has been sanitized (faces and plates blurred), so nobody is ever pointed at the raw original.
class OwnTrashSerializer < ApplicationSerializer
  THUMB_SIZE = [360, 360].freeze

  def initialize(record, urls:)
    super
    @urls = urls
  end

  def as_json(*)
    {
      id: record.id,
      ai_status: record.ai_status,
      kind: record.kind,
      stage: ReportStage.of(record),
      done: !record.pending?,
      severity: record.severity,
      trash_types: record.trash_types,
      taken_at: record.taken_at,
      lat: record.lonlat.y,
      lng: record.lonlat.x,
      h3_index: record.h3_index,
      published: record.published?,
      can_publish: record.publishable?,
      photo_ready: photo_ready?,
      photo_url: photo_ready? ? @urls.url_for(record.photo) : nil,
      thumb_url: photo_ready? ? @urls.url_for(record.photo.variant(resize_to_fill: THUMB_SIZE)) : nil
    }
  end

  private

  # a rejected or taken-down report has no file any more
  def photo_ready?
    record.sanitized_at.present? && record.photo.attached?
  end
end
