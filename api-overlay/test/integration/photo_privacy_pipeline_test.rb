require "test_helper"

# End to end, through the real API and the real jobs: upload a photo that has GPS and camera data
# in its EXIF, and check what is stored, what is shown, and what happens when things go wrong.
# Needs libvips (see README).
class PhotoPrivacyPipelineTest < ActionDispatch::IntegrationTest
  NOW = Time.utc(2026, 10, 21, 12)
  PLATE = { kind: "license_plate", x: 0.25, y: 0.25, width: 0.25, height: 0.25 }.freeze
  INSIDE = [55, 40, 40, 32].freeze # inside the redaction box on the 200x150 fixture
  BBOX = "-48.0,-16.0,-47.7,-15.6".freeze

  setup { @device = create_device }

  # The fixture's EXIF says: taken 2026-10-20 14:30, at -15.7942, -47.8825.
  def upload_exif_photo(lat: -15.7942, lng: -47.8825)
    post "/api/v1/trashes",
         params: { photo: uploaded_photo("exif_gps.jpg"), lat: lat, lng: lng, taken_at: "2026-10-20T14:30:00Z" },
         headers: { "X-Device-Token" => @device.token }
    assert_response :accepted
    Trash.find(response.parsed_body["id"])
  end

  test "an uploaded photo is stripped, blurred and validated before it reaches the map" do
    travel_to NOW do
      PrivacyDetector.provider = ->(_bytes) { [PLATE] }
      original = decode(file_fixture("exif_gps.jpg").binread)

      perform_enqueued_jobs { upload_exif_photo }
      trash = Trash.last

      assert_predicate trash, :validated?
      assert_not_nil trash.sanitized_at
      assert_equal({ "license_plate" => 1 }, trash.photo_meta["redactions"])

      stored = trash.photo.download
      assert_not PhotoMetadata.read(stored).exif?, "GPS and camera data must be gone"
      assert_not_includes stored.b, "FakeCam"
      assert_operator deviation_in(decode(stored), INSIDE), :<, deviation_in(original, INSIDE) * 0.35

      get "/api/v1/heatmap", params: { bbox: BBOX }
      features = response.parsed_body["features"]
      assert_equal 1, features.size
      assert_operator features.first["properties"]["score"], :>, 3.5 # severity 4, a day old

      get "/api/v1/trashes", params: { lat: -15.7942, lng: -47.8825 }
      assert_equal [trash.id], response.parsed_body.map { |t| t["id"] }
    end
  end

  test "the AI is shown the sanitized photo, never the original" do
    travel_to NOW do
      PrivacyDetector.provider = ->(_bytes) { [PLATE] }
      seen = nil
      TrashVision.provider = ->(photo) { seen = photo.download; vision_result }

      perform_enqueued_jobs { upload_exif_photo }

      assert_not_nil seen
      assert_not PhotoMetadata.read(seen).exif?
      assert_not_includes seen.b, "FakeCam"
    end
  end

  test "nothing is public while the photo is still being processed" do
    travel_to NOW do
      trash = upload_exif_photo # jobs queued, not run

      assert_predicate trash, :pending?
      get "/api/v1/trashes/#{trash.id}"
      assert_response :not_found
      get "/api/v1/trashes", params: { lat: -15.7942, lng: -47.8825 }
      assert_empty response.parsed_body
      get "/api/v1/heatmap", params: { bbox: BBOX }
      assert_empty response.parsed_body["features"]

      get "/api/v1/me/trashes", headers: { "X-Device-Token" => @device.token }
      assert_equal false, response.parsed_body.first["photo_ready"]
      assert_nil response.parsed_body.first["photo_url"]
    end
  end

  test "fails closed: when the detector is down the photo is held, private, and never analyzed" do
    travel_to NOW do
      PrivacyDetector.provider = ->(_bytes) { raise "detector is down" }
      vision_calls = 0
      TrashVision.provider = ->(_photo) { vision_calls += 1; vision_result }

      perform_enqueued_jobs { upload_exif_photo }
      trash = Trash.last

      assert_predicate trash, :needs_review?
      assert_nil trash.sanitized_at
      assert_equal 0, vision_calls

      get "/api/v1/trashes/#{trash.id}"
      assert_response :not_found
      get "/api/v1/heatmap", params: { bbox: BBOX }
      assert_empty response.parsed_body["features"]
      get "/api/v1/me/trashes", headers: { "X-Device-Token" => @device.token }
      assert_nil response.parsed_body.first["photo_url"], "the raw original must never be linked"
    end
  end

  test "a photo whose EXIF says it was taken far away goes to review instead of the map" do
    travel_to NOW do
      perform_enqueued_jobs { upload_exif_photo(lat: -23.5505, lng: -46.6333) } # claims Sao Paulo
      trash = Trash.last

      assert_predicate trash, :needs_review?
      assert_equal "metadata_mismatch", trash.ai_payload["reason"]
      assert_not_nil trash.sanitized_at, "it is still sanitized, just not published"

      get "/api/v1/trashes/#{trash.id}"
      assert_response :not_found
      get "/api/v1/heatmap", params: { bbox: "-47,-24,-46,-23" }
      assert_empty response.parsed_body["features"]
    end
  end

  test "a corrupt upload is rejected and deleted" do
    travel_to NOW do
      post "/api/v1/trashes",
           params: { photo: uploaded_photo("corrupt.jpg"), lat: -15.7942, lng: -47.8825, taken_at: "2026-10-20T14:30:00Z" },
           headers: { "X-Device-Token" => @device.token }
      assert_response :accepted

      trash = Trash.find(response.parsed_body["id"])
      perform_enqueued_jobs { SanitizePhotoJob.perform_later(trash.id) }

      assert_predicate trash.reload, :rejected?
      assert_not trash.photo.attached?
    end
  end
end
