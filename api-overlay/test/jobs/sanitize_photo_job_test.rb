require "test_helper"

# Needs libvips (see README).
class SanitizePhotoJobTest < ActiveSupport::TestCase
  FACE = { kind: "face", x: 0.25, y: 0.25, width: 0.25, height: 0.25 }.freeze
  INSIDE = [55, 40, 40, 32].freeze # inside the padded redaction box of FACE on a 200x150 photo

  test "replaces the stored photo with a sanitized copy that keeps GPS and camera EXIF" do
    trash = create_trash(fixture: "exif_gps.jpg")
    assert PhotoMetadata.read(trash.photo.download).exif?, "the upload starts with EXIF"

    SanitizePhotoJob.perform_now(trash.id)

    trash.reload
    stored = trash.photo.download
    assert_predicate PhotoMetadata.read(stored), :gps?
    assert_includes stored.b, "FakeCam"
    assert_equal true, trash.photo_meta["metadata_kept"]
    assert_equal "image/jpeg", trash.photo.content_type
    assert_not_nil trash.sanitized_at
  end

  test "with STRIP_PHOTO_METADATA=true the stored photo has no EXIF at all" do
    trash = create_trash(fixture: "exif_gps.jpg")

    with_env("STRIP_PHOTO_METADATA" => "true") { SanitizePhotoJob.perform_now(trash.id) }

    trash.reload
    stored = trash.photo.download
    assert_not PhotoMetadata.read(stored).exif?
    assert_not_includes stored.b, "FakeCam"
    assert_equal false, trash.photo_meta["metadata_kept"]
  end

  test "deletes the original file, not just the database row" do
    trash = create_trash(fixture: "exif_gps.jpg")
    original_blob_id = trash.photo.blob.id
    original_key = trash.photo.blob.key

    perform_enqueued_jobs(only: ActiveStorage::PurgeJob) { SanitizePhotoJob.perform_now(trash.id) }

    assert_not ActiveStorage::Blob.exists?(original_blob_id)
    assert_not ActiveStorage::Blob.service.exist?(original_key)
    assert ActiveStorage::Blob.exists?(trash.reload.photo.blob.id)
  end

  test "blurs the regions the detector finds and records what it did" do
    PrivacyDetector.provider = ->(_bytes) { [FACE] }
    trash = create_trash(fixture: "exif_gps.jpg")
    before = deviation_in(decode(trash.photo.download), INSIDE)

    SanitizePhotoJob.perform_now(trash.id)

    trash.reload
    after = deviation_in(decode(trash.photo.download), INSIDE)
    assert_operator after, :<, before * 0.35
    assert_equal({ "face" => 1 }, trash.photo_meta["redactions"])
  end

  test "records what the EXIF data said, before it is thrown away" do
    trash = create_trash(fixture: "exif_gps.jpg")

    SanitizePhotoJob.perform_now(trash.id)

    meta = trash.reload.photo_meta
    assert_equal true, meta["exif_present"]
    assert_equal "2026-10-20T14:30:00Z", meta["exif_taken_at"]
    assert_operator meta["exif_distance_m"], :<, 5 # the photo is where the report says
    assert_equal({}, meta["redactions"])
  end

  test "records how far the EXIF position is from the reported one" do
    trash = create_trash(fixture: "exif_gps.jpg", lng: -46.6333, lat: -23.5505) # claims Sao Paulo

    SanitizePhotoJob.perform_now(trash.id)

    trash.reload
    assert_in_delta 872_303, trash.photo_meta["exif_distance_m"], 1_000
    assert_predicate trash, :metadata_suspicious?
  end

  test "a photo without EXIF is fine, there is just nothing to compare" do
    trash = create_trash(fixture: "plain.jpg")

    SanitizePhotoJob.perform_now(trash.id)

    meta = trash.reload.photo_meta
    assert_equal false, meta["exif_present"]
    assert_not meta.key?("exif_taken_at")
    assert_not meta.key?("exif_distance_m")
    assert_not_predicate trash, :metadata_suspicious?
  end

  test "applies the EXIF rotation" do
    trash = create_trash(fixture: "exif_rotated.jpg") # stored 120x80, displayed 80x120

    SanitizePhotoJob.perform_now(trash.id)

    image = decode(trash.reload.photo.download)
    assert_equal [80, 120], [image.width, image.height]
  end

  test "hands over to validation once the photo is safe" do
    trash = create_trash

    assert_enqueued_with(job: ValidateTrashJob, args: [trash.id]) { SanitizePhotoJob.perform_now(trash.id) }
  end

  test "running twice does nothing the second time" do
    trash = create_trash
    SanitizePhotoJob.perform_now(trash.id)
    trash.reload
    blob_id = trash.photo.blob.id
    sanitized_at = trash.sanitized_at

    assert_no_enqueued_jobs(only: ValidateTrashJob) { SanitizePhotoJob.perform_now(trash.id) }

    trash.reload
    assert_equal blob_id, trash.photo.blob.id
    assert_equal sanitized_at, trash.sanitized_at
  end

  test "fails closed: if the detector is down the report stays private and goes to review" do
    PrivacyDetector.provider = ->(_bytes) { raise "detector is down" }
    vision_calls = 0
    TrashVision.provider = ->(_photo) { vision_calls += 1; vision_result }
    trash = create_trash(fixture: "exif_gps.jpg")

    perform_enqueued_jobs { SanitizePhotoJob.perform_later(trash.id) } # retries, then gives up

    trash.reload
    assert_predicate trash, :needs_review?
    assert_nil trash.sanitized_at
    assert_match(/sanitize_failed: RuntimeError/, trash.ai_payload["hold_reason"])
    assert_equal 0, vision_calls, "the AI must not see an unsanitized photo"
    assert_not_includes Trash.for_heatmap.pluck(:id), trash.id
  end

  test "retries a failing detector before giving up" do
    attempts = 0
    PrivacyDetector.provider = ->(_bytes) { attempts += 1; raise "flaky" }
    trash = create_trash

    perform_enqueued_jobs { SanitizePhotoJob.perform_later(trash.id) }

    assert_equal 5, attempts
  end

  test "recovers when the detector comes back during the retries" do
    attempts = 0
    PrivacyDetector.provider = ->(_bytes) { attempts += 1; attempts < 3 ? raise("flaky") : [] }
    trash = create_trash

    perform_enqueued_jobs(only: SanitizePhotoJob) { SanitizePhotoJob.perform_later(trash.id) }

    assert_equal 3, attempts
    assert_not_nil trash.reload.sanitized_at
    assert_predicate trash, :pending? # validation is a separate job
  end

  test "rejects a file that cannot be decoded and deletes it" do
    trash = create_trash(fixture: "corrupt.jpg")

    perform_enqueued_jobs { SanitizePhotoJob.perform_later(trash.id) }

    trash.reload
    assert_predicate trash, :rejected?
    assert_equal "unreadable_image", trash.ai_payload["reason"]
    assert_not trash.photo.attached?
    assert_nil trash.sanitized_at
  end

  test "ignores a report that no longer exists" do
    assert_nothing_raised { SanitizePhotoJob.perform_now(0) }
  end
end
