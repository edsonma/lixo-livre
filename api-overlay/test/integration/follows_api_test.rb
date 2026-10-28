require "test_helper"

class FollowsApiTest < ActionDispatch::IntegrationTest
  setup do
    @user = create_user
    @trash = create_published_trash(severity: 60)
    RefreshHeatCellJob.perform_now(@trash.h3_index)
  end

  test "needs a login" do
    post "/api/v1/follows", params: { h3_index: @trash.h3_index }
    assert_response :unauthorized
    get "/api/v1/notifications"
    assert_response :unauthorized
  end

  test "follow, list, and unfollow a place" do
    sign_in @user
    post "/api/v1/follows", params: { h3_index: @trash.h3_index }
    assert_response :created
    post "/api/v1/follows", params: { h3_index: @trash.h3_index } # twice is fine
    assert_response :created
    assert_equal 1, @user.follows.count

    get "/api/v1/follows"
    assert_equal [@trash.h3_index], response.parsed_body.map { |f| f["h3"] }

    get "/api/v1/places/#{@trash.h3_index}"
    assert_equal true, response.parsed_body["following"]

    delete "/api/v1/follows/#{@trash.h3_index}"
    assert_response :no_content
    assert_equal 0, @user.follows.count
  end

  test "unknown or malformed places cannot be followed" do
    sign_in @user
    post "/api/v1/follows", params: { h3_index: "nope" }
    assert_response :not_found
    post "/api/v1/follows", params: { h3_index: "8a" + "0" * 13 }
    assert_response :not_found
  end

  test "notifications list newest first and can be marked read" do
    sign_in @user
    old = @user.notifications.create!(kind: "worse", h3_index: @trash.h3_index, score: 70, previous_score: 40, created_at: 2.days.ago)
    new = @user.notifications.create!(kind: "cleaned", h3_index: @trash.h3_index, score: 0, previous_score: 70)

    get "/api/v1/notifications"
    body = response.parsed_body
    assert_equal 2, body["unread"]
    assert_equal [new.id, old.id], body["items"].map { |i| i["id"] }

    post "/api/v1/notifications/read"
    assert_response :no_content
    get "/api/v1/notifications"
    assert_equal 0, response.parsed_body["unread"]
  end

  test "someone else's notifications are not shown" do
    other = create_user
    other.notifications.create!(kind: "worse", h3_index: @trash.h3_index)
    sign_in @user
    get "/api/v1/notifications"
    assert_empty response.parsed_body["items"]
  end
end
