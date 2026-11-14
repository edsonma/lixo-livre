# A report in the moderation queue, for admins and moderators (so it carries the uploader's email).
# kind is "held" (the pipeline would not publish it by itself) or "flagged" (people reported it).
class ReviewSerializer < ApplicationSerializer
  def initialize(record, urls:, kind:)
    super(record)
    @urls = urls
    @kind = kind
  end

  def as_json(*)
    {
      id: record.id,
      kind: @kind,
      reason: reason,
      flags: record.flags.map(&:reason).tally,
      severity: record.severity,
      trash_types: record.trash_types,
      ai_confidence: record.ai_confidence,
      extra_info: record.extra_info,
      taken_at: record.taken_at,
      created_at: record.created_at,
      lat: record.lonlat.y,
      lng: record.lonlat.x,
      exif_distance_m: (record.photo_meta || {})["exif_distance_m"],
      hold_reason: payload["hold_reason"],
      uploader: record.user && { id: record.user_id, name: record.user.name, email: record.user.email },
      hidden: record.hidden_at.present?,
      photo_protected: photo_protected?,
      photo_url: photo_protected? && record.photo.attached? ? @urls.url_for(record.photo) : nil
    }
  end

  private

  # An un-protected photo (the privacy step did not finish) is never shown, even to admins.
  def photo_protected?
    record.sanitized_at.present?
  end

  def payload
    record.ai_payload || {}
  end

  def reason
    return "flagged" if @kind == "flagged"
    return payload["reason"] if payload["reason"].present?
    return "failed" if payload["hold_reason"].present?

    record.ai_confidence ? "low_confidence" : "other"
  end
end
