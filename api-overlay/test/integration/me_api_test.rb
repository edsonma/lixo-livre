require "test_helper"

class MeApiTest < ActionDispatch::IntegrationTest
  setup { @device = create_device }

  def feed
    get "/api/v1/me/trashes", headers: { "X-Device-Token" => @device.token }
    response.parsed_body
  end

  test "needs a device token" do
    get "/api/v1/me/trashes"
    assert_response :unauthorized

    get "/api/v1/me/trashes", headers: { "X-Device-Token" => "made-up" }
    assert_response :unauthorized
  end

  test "lists only this device's reports, newest first, whatever their status" do
    older = create_trash(device: @device, taken_at: 2.days.ago)
    newer = create_published_trash(device: @device, taken_at: 1.hour.ago)
    create_published_trash # somebody else's

    body = feed

    assert_response :success
    assert_equal [newer.id, older.id], body.map { |t| t["id"] }
    assert_equal %w[validated pending], body.map { |t| t["ai_status"] }
  end

  test "includes the AI's verdict once there is one" do
    create_published_trash(device: @device, severity: 4)

    entry = feed.first

    assert_equal 4, entry["severity"]
    assert_equal %w[plastic], entry["trash_types"]
  end

  test "never links a photo that has not been sanitized yet" do
    create_trash(device: @device)

    entry = feed.first

    assert_equal false, entry["photo_ready"]
    assert_nil entry["photo_url"]
  end

  test "links the photo once it is sanitized, even while it waits for review" do
    trash = create_trash(device: @device)
    trash.update_columns(sanitized_at: Time.current, ai_status: "needs_review")

    entry = feed.first

    assert_equal true, entry["photo_ready"]
    assert_match(/active_storage/, entry["photo_url"])
  end

  test "is empty for a brand new device" do
    assert_equal [], feed
  end
end
