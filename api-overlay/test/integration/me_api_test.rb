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
    create_published_trash(device: @device, severity: 80)

    entry = feed.first

    assert_equal 80, entry["severity"]
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

  # --- polling one report after upload ---

  def show_report(id, token: @device.token)
    get "/api/v1/me/trashes/#{id}", headers: { "X-Device-Token" => token }
    response.parsed_body
  end

  test "show walks through the stages of the pipeline" do
    trash = create_trash(device: @device)
    body = show_report(trash.id)
    assert_equal "protecting_photo", body["stage"]
    assert_equal false, body["done"]
    assert_nil body["severity"]

    trash.update_columns(sanitized_at: Time.current)
    assert_equal "analyzing", show_report(trash.id)["stage"]

    trash.update_columns(ai_status: "validated", severity: 80, trash_types: %w[plastic])
    body = show_report(trash.id)
    assert_equal "scored", body["stage"]
    assert_equal true, body["done"]
    assert_equal 80, body["severity"]
  end

  test "show reports not_trash and in_review as finished" do
    trash = create_published_trash(device: @device)

    trash.update_columns(ai_status: "rejected", severity: nil)
    assert_equal ["not_trash", true], show_report(trash.id).values_at("stage", "done")

    trash.update_columns(ai_status: "needs_review")
    assert_equal ["in_review", true], show_report(trash.id).values_at("stage", "done")
  end

  test "show never links an unsanitized photo" do
    trash = create_trash(device: @device)

    assert_nil show_report(trash.id)["photo_url"]
  end

  test "show is private to the device that uploaded the report" do
    theirs = create_published_trash

    show_report(theirs.id)

    assert_response :not_found
  end

  test "show needs a device token" do
    get "/api/v1/me/trashes/#{create_published_trash(device: @device).id}"

    assert_response :unauthorized
  end
end
