# Runs right after upload, BEFORE the AI sees the photo or anyone can see it:
# reads the EXIF fields we need, then replaces the stored photo with a sanitized copy
# (faces and license plates blurred, EXIF kept in a cleaned form, see PhotoSanitizer) and deletes
# the original file.
#
# Fail closed: if sanitizing cannot be completed (detector down, ...) the report goes to
# `needs_review` and stays private. An unsanitized photo is never published.
class SanitizePhotoJob < ApplicationJob
  queue_as :default

  retry_on StandardError, wait: :polynomially_longer, attempts: 5 do |job, error|
    Trash.find_by(id: job.arguments.first)&.hold_for_review!("sanitize_failed: #{error.class}")
  end
  discard_on ActiveRecord::RecordNotFound

  def perform(trash_id)
    trash = Trash.find(trash_id)
    return if trash.sanitized_at # already done (job ran twice)

    original = trash.photo.download
    metadata = PhotoMetadata.read(original)

    begin
      result = PhotoSanitizer.call(original)
    rescue PhotoSanitizer::InvalidImage
      reject_unreadable(trash)
      return
    end

    # One save: swaps the photo (the old blob is purged in the background), marks it safe.
    trash.update!(
      photo: { io: StringIO.new(result.data), filename: "trash-#{trash.id}.jpg", content_type: result.content_type },
      sanitized_at: Time.current,
      photo_meta: build_meta(trash, metadata, result)
    )

    ValidateTrashJob.perform_later(trash.id)
  end

  private

  # A file we cannot decode cannot be sanitized, so it must not be kept either.
  def reject_unreadable(trash)
    trash.update_columns(ai_status: "rejected", ai_payload: { "reason" => "unreadable_image" }, updated_at: Time.current)
    trash.photo.purge_later
  end

  def build_meta(trash, metadata, result)
    meta = { "exif_present" => metadata.exif?, "metadata_kept" => result.metadata_kept, "redactions" => result.redactions }
    meta["exif_taken_at"] = metadata.taken_at.utc.iso8601 if metadata.taken_at
    if metadata.gps?
      meta["exif_distance_m"] = Geo.distance_m(trash.lonlat.y, trash.lonlat.x, metadata.lat, metadata.lng).round
    end
    meta
  end
end
