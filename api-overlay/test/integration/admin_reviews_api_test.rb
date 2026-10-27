require "test_helper"

class AdminReviewsApiTest < ActionDispatch::IntegrationTest
  setup do
    @admin = create_user(role: :admin)
    sign_in @admin
  end

  def json_post(path, body = {})
    post path, params: body.to_json, headers: { "Content-Type" => "application/json" }
  end

  # A report the pipeline held: protected photo, no verdict.
  def held_trash(payload: { "reason" => "metadata_mismatch" }, sanitized: true, **attrs)
    create_trash(**attrs).tap do |t|
      t.update_columns(ai_status: "needs_review", ai_payload: payload, sanitized_at: (Time.current if sanitized))
    end
  end

  def flag!(trash, reason: "privacy")
    Flag.create!(trash: trash, device: create_device, reason: reason)
  end

  # --- who may look ---

  test "visitors and ordinary users cannot see the queue" do
    delete "/api/v1/session"
    get "/api/v1/admin/reviews"
    assert_response :unauthorized

    sign_in create_user
    get "/api/v1/admin/reviews"
    assert_response :forbidden
  end

  test "moderators can, as well as admins" do
    sign_in create_user(role: :moderator)

    get "/api/v1/admin/reviews"

    assert_response :success
  end

  # --- the list ---

  test "lists held reports and published reports that people flagged" do
    held = held_trash
    flagged = create_published_trash
    flag!(flagged)
    create_published_trash # nothing wrong with this one
    create_draft_trash     # a draft is its author's business, not the queue's

    get "/api/v1/admin/reviews"

    body = response.parsed_body
    assert_equal({ "held" => 1, "flagged" => 1 }, body["counts"])
    assert_equal [held.id], body["held"].map { |r| r["id"] }
    assert_equal [flagged.id], body["flagged"].map { |r| r["id"] }
    assert_equal "metadata_mismatch", body["held"].first["reason"]
    assert_equal({ "privacy" => 1 }, body["flagged"].first["flags"])
  end

  test "says why a report was held" do
    held_trash(payload: { "hold_reason" => "sanitize_failed: PrivacyDetector::NotConfigured" })
    held_trash(payload: {}).update_columns(ai_confidence: 0.4)

    get "/api/v1/admin/reviews"

    assert_equal %w[failed low_confidence].sort, response.parsed_body["held"].map { |r| r["reason"] }.sort
  end

  test "a photo that was never protected is not shown, even to admins" do
    held_trash(sanitized: false)

    get "/api/v1/admin/reviews"

    entry = response.parsed_body["held"].first
    assert_equal false, entry["photo_protected"]
    assert_nil entry["photo_url"]
  end

  test "a protected photo is shown, with where it was taken and who sent it" do
    user = create_user(name: "Rita", email: "rita@example.com")
    held_trash(user: user)

    get "/api/v1/admin/reviews"

    entry = response.parsed_body["held"].first
    assert_match(/active_storage/, entry["photo_url"])
    assert_equal({ "id" => user.id, "name" => "Rita", "email" => "rita@example.com" }, entry["uploader"])
    assert_in_delta(-15.7942, entry["lat"], 0.001)
  end

  # --- approving and rejecting held reports ---

  test "approving a held report gives it the chosen severity and puts it on the map" do
    trash = held_trash

    assert_enqueued_with(job: RefreshHeatCellJob) do
      json_post "/api/v1/admin/reviews/#{trash.id}/approve", severity: 70, trash_types: %w[plastic glass]
    end

    assert_response :success
    trash.reload
    assert_predicate trash, :validated?
    assert_equal [70, %w[plastic glass]], [trash.severity, trash.trash_types]
    assert_includes Trash.for_heatmap.pluck(:id), trash.id
    assert_equal @admin.id, trash.ai_payload["reviewer_id"]
  end

  test "approving needs a severity from 0 to 100" do
    trash = held_trash

    json_post "/api/v1/admin/reviews/#{trash.id}/approve", severity: 150
    assert_response :unprocessable_entity
    json_post "/api/v1/admin/reviews/#{trash.id}/approve", severity: "lots"
    assert_response :unprocessable_entity
    json_post "/api/v1/admin/reviews/#{trash.id}/approve", {}
    assert_response :bad_request

    assert_predicate trash.reload, :needs_review?
  end

  test "a report whose photo is not protected cannot be approved" do
    trash = held_trash(sanitized: false)

    json_post "/api/v1/admin/reviews/#{trash.id}/approve", severity: 50

    assert_response :unprocessable_entity
    assert_equal "not_reviewable", response.parsed_body["error"]
    assert_not_includes Trash.for_heatmap.pluck(:id), trash.id
  end

  test "rejecting a held report keeps it off the map and deletes its photo" do
    trash = held_trash

    assert_enqueued_with(job: ActiveStorage::PurgeJob) { json_post "/api/v1/admin/reviews/#{trash.id}/reject" }

    assert_response :success
    assert_predicate trash.reload, :rejected?
    assert_not_includes Trash.for_heatmap.pluck(:id), trash.id
  end

  test "ordinary users cannot approve or reject" do
    trash = held_trash
    sign_in create_user

    json_post "/api/v1/admin/reviews/#{trash.id}/approve", severity: 50
    assert_response :forbidden
    json_post "/api/v1/admin/reviews/#{trash.id}/reject"
    assert_response :forbidden
    assert_predicate trash.reload, :needs_review?
  end

  test "a report that is not waiting for anything cannot be reviewed" do
    trash = create_published_trash

    json_post "/api/v1/admin/reviews/#{trash.id}/approve", severity: 50
    assert_response :unprocessable_entity
    json_post "/api/v1/admin/reviews/#{trash.id}/reject"
    assert_response :unprocessable_entity
    assert_includes Trash.for_heatmap.pluck(:id), trash.id
  end

  # --- flagged photos ---

  test "keeping a flagged photo dismisses the flags and shows it again" do
    trash = create_published_trash
    flag!(trash)
    trash.hide!

    json_post "/api/v1/admin/reviews/#{trash.id}/approve"

    assert_response :success
    assert_nil trash.reload.hidden_at
    assert_equal 0, trash.flags.pending.count
    assert_equal ["dismissed"], trash.flags.map(&:status)
    assert_includes Trash.for_heatmap.pluck(:id), trash.id
  end

  test "taking a flagged photo down hides it and resolves the flags" do
    trash = create_published_trash
    flag!(trash)

    json_post "/api/v1/admin/reviews/#{trash.id}/reject"

    assert_response :success
    assert_not_nil trash.reload.hidden_at
    assert_equal ["resolved"], trash.flags.map(&:status)
    assert_not_includes Trash.for_heatmap.pluck(:id), trash.id
  end

  test "the status of the login shows whether the person can moderate" do
    get "/api/v1/session"

    assert_equal [true, true], response.parsed_body["user"].values_at("admin", "moderator")
  end
end
