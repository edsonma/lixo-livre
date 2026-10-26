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

  # --- publishing or discarding a scored report ---

  def publish_report(id, token: @device.token)
    post "/api/v1/me/trashes/#{id}/publish", headers: { "X-Device-Token" => token }
  end

  test "a scored report can be published by its author, and then shows as published" do
    trash = create_draft_trash(device: @device)
    body = show_report(trash.id)
    assert_equal ["scored", true, false], body.values_at("stage", "can_publish", "published")

    publish_report(trash.id)

    assert_response :success
    assert_equal ["published", false, true], response.parsed_body.values_at("stage", "can_publish", "published")
    assert_includes Trash.for_heatmap.pluck(:id), trash.id
  end

  test "the report's own position is part of the answer, for the analysis screen" do
    trash = create_draft_trash(device: @device, lng: -47.9, lat: -15.8)
    body = show_report(trash.id)
    assert_in_delta(-15.8, body["lat"], 0.0001)
    assert_in_delta(-47.9, body["lng"], 0.0001)
  end

  test "only a scored report with a sanitized photo can be published" do
    pending_report = create_trash(device: @device)
    publish_report(pending_report.id)
    assert_response :unprocessable_entity
    assert_equal "not_publishable", response.parsed_body["error"]

    unsanitized = create_draft_trash(device: @device).tap { |t| t.update_columns(sanitized_at: nil) }
    publish_report(unsanitized.id)
    assert_response :unprocessable_entity
    assert_not_includes Trash.for_heatmap.pluck(:id), unsanitized.id
  end

  test "publishing twice is refused and keeps the first publication time" do
    trash = create_draft_trash(device: @device)
    publish_report(trash.id)
    first = trash.reload.published_at

    publish_report(trash.id)

    assert_response :unprocessable_entity
    assert_equal first, trash.reload.published_at
  end

  test "nobody can publish or discard somebody else's report" do
    trash = create_draft_trash # another device's
    publish_report(trash.id)
    assert_response :not_found
    delete "/api/v1/me/trashes/#{trash.id}", headers: { "X-Device-Token" => @device.token }
    assert_response :not_found
    assert Trash.exists?(trash.id)
    assert_nil trash.reload.published_at
  end

  test "publishing and discarding need a device token" do
    trash = create_draft_trash(device: @device)
    post "/api/v1/me/trashes/#{trash.id}/publish"
    assert_response :unauthorized
    delete "/api/v1/me/trashes/#{trash.id}"
    assert_response :unauthorized
  end

  test "Voltar: an unpublished report can be thrown away" do
    trash = create_draft_trash(device: @device)

    delete "/api/v1/me/trashes/#{trash.id}", headers: { "X-Device-Token" => @device.token }

    assert_response :no_content
    assert_not Trash.exists?(trash.id)
  end

  test "a published report cannot be thrown away through this endpoint" do
    trash = create_published_trash(device: @device)

    delete "/api/v1/me/trashes/#{trash.id}", headers: { "X-Device-Token" => @device.token }

    assert_response :unprocessable_entity
    assert_equal "already_published", response.parsed_body["error"]
    assert Trash.exists?(trash.id)
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
