require "test_helper"

class TrashesApiTest < ActionDispatch::IntegrationTest
  def auth(device)
    { "X-Device-Token" => device.token }
  end

  def upload(device: create_device, **overrides)
    params = {
      photo: uploaded_photo("plain.jpg"), lat: -15.7942, lng: -47.8825,
      taken_at: 1.hour.ago.iso8601, extra_info: "pile of bags"
    }.merge(overrides)
    post "/api/v1/trashes", params: params.compact, headers: device ? auth(device) : {}
  end

  # --- POST /trashes ---

  test "POST creates a pending report and queues sanitizing" do
    device = create_device

    assert_enqueued_with(job: SanitizePhotoJob) { upload(device: device) }

    assert_response :accepted
    body = response.parsed_body
    assert_equal "pending", body["ai_status"]
    trash = Trash.find(body["id"])
    assert_equal device, trash.device
    assert_equal "pile of bags", trash.extra_info
    assert_in_delta(-15.7942, trash.lonlat.y, 1e-6)
    assert_in_delta(-47.8825, trash.lonlat.x, 1e-6)
    assert trash.photo.attached?
    assert_nil trash.sanitized_at
  end

  test "POST attributes the report to the logged-in user behind the device" do
    user = create_user
    upload(device: create_device(user: user))

    assert_equal user, Trash.find(response.parsed_body["id"]).user
  end

  test "POST from an anonymous device leaves the user empty" do
    upload

    assert_nil Trash.find(response.parsed_body["id"]).user
  end

  test "POST needs a known device token" do
    assert_no_difference("Trash.count") do
      upload(device: nil)
      assert_response :unauthorized

      post "/api/v1/trashes", params: { photo: uploaded_photo, lat: 1, lng: 1, taken_at: Time.current.iso8601 },
                              headers: { "X-Device-Token" => "made-up" }
      assert_response :unauthorized
    end
  end

  test "POST without a photo is rejected" do
    assert_no_difference("Trash.count") { upload(photo: nil) }

    assert_response :unprocessable_entity
    assert response.parsed_body["errors"].key?("photo")
  end

  test "POST with something that is not an image is rejected" do
    assert_no_difference("Trash.count") { upload(photo: uploaded_photo("not_an_image.pdf", "application/pdf")) }

    assert_response :unprocessable_entity
    assert response.parsed_body["errors"].key?("photo")
  end

  test "POST with an unreadable time is rejected" do
    assert_no_difference("Trash.count") { upload(taken_at: "sometime last week") }

    assert_response :unprocessable_entity
    assert response.parsed_body["errors"].key?("taken_at")
  end

  test "POST without a position is a bad request" do
    upload(lat: nil)
    assert_response :bad_request
    assert response.parsed_body["errors"].key?("lat")

    upload(lng: nil)
    assert_response :bad_request
    assert response.parsed_body["errors"].key?("lng")
  end

  # --- GET /trashes (photos near a hotspot) ---

  test "GET index returns published photos near the point, newest first" do
    user = create_user(name: "Ana")
    older = create_published_trash(taken_at: 3.days.ago, device: create_device(user: user), user: user)
    newer = create_published_trash(taken_at: 1.day.ago, lat: -15.7937) # ~56 m away, anonymous
    create_published_trash(lat: -15.7492) # 5 km away

    get "/api/v1/trashes", params: { lat: -15.7942, lng: -47.8825, radius: 100 }

    assert_response :success
    body = response.parsed_body
    assert_equal [newer.id, older.id], body.map { |t| t["id"] }

    first = body.first
    assert_equal %w[extra_info id lat lng photo_url severity taken_at trash_types uploader], first.keys.sort
    assert_match(/active_storage/, first["photo_url"])
    assert_nil first["uploader"], "anonymous reports have no uploader"
    assert_equal({ "id" => user.id, "name" => "Ana" }, body.last["uploader"])
  end

  test "GET index never shows photos that are not public yet" do
    shown = create_published_trash
    create_trash                                                                   # pending
    create_trash.tap { |t| t.update_columns(ai_status: "validated", severity: 3) } # validated, never sanitized
    create_published_trash.tap(&:hide!)                                            # flagged away
    create_published_trash.tap { |t| t.update_columns(ai_status: "rejected") }

    get "/api/v1/trashes", params: { lat: -15.7942, lng: -47.8825 }

    assert_equal [shown.id], response.parsed_body.map { |t| t["id"] }
  end

  test "GET index caps the search radius at 500 m" do
    create_published_trash(lat: -15.7762) # ~2 km north

    get "/api/v1/trashes", params: { lat: -15.7942, lng: -47.8825, radius: 5_000 }

    assert_empty response.parsed_body
  end

  test "GET index needs a position" do
    get "/api/v1/trashes", params: { lat: -15.79 }

    assert_response :bad_request
  end

  test "GET index is public: no device token needed" do
    create_published_trash

    get "/api/v1/trashes", params: { lat: -15.7942, lng: -47.8825 }

    assert_response :success
  end

  # --- GET /trashes/:id ---

  test "GET show returns one published report" do
    trash = create_published_trash(severity: 80)

    get "/api/v1/trashes/#{trash.id}"

    assert_response :success
    assert_equal trash.id, response.parsed_body["id"]
    assert_equal 80, response.parsed_body["severity"]
    assert_equal %w[plastic], response.parsed_body["trash_types"]
  end

  test "GET show is a 404 for anything that is not public" do
    pending_trash = create_trash
    hidden = create_published_trash.tap(&:hide!)
    unsanitized = create_trash.tap { |t| t.update_columns(ai_status: "validated") }

    [pending_trash.id, hidden.id, unsanitized.id, 0].each do |id|
      get "/api/v1/trashes/#{id}"

      assert_response :not_found, "trash #{id} should not be visible"
    end
  end
end
