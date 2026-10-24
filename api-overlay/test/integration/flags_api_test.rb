require "test_helper"

class FlagsApiTest < ActionDispatch::IntegrationTest
  setup { @trash = create_published_trash }

  def flag(trash: @trash, device: create_device, reason: "privacy")
    post "/api/v1/trashes/#{trash.id}/flags", params: { reason: reason }, headers: { "X-Device-Token" => device.token }
  end

  test "POST creates a flag" do
    device = create_device

    assert_difference("Flag.count", 1) { flag(device: device) }

    assert_response :created
    created = Flag.find(response.parsed_body["id"])
    assert_equal [@trash, device, "privacy", "pending"], [created.trash, created.device, created.reason, created.status]
  end

  test "POST needs a device token" do
    assert_no_difference("Flag.count") do
      post "/api/v1/trashes/#{@trash.id}/flags", params: { reason: "privacy" }
    end

    assert_response :unauthorized
  end

  test "the same device cannot flag a photo twice" do
    device = create_device
    flag(device: device)

    assert_no_difference("Flag.count") { flag(device: device) }

    assert_response :unprocessable_entity
    assert response.parsed_body["errors"].key?("device_id")
  end

  test "an unknown reason is rejected" do
    assert_no_difference("Flag.count") { flag(reason: "i just dislike it") }

    assert_response :unprocessable_entity
    assert response.parsed_body["errors"].key?("reason")
  end

  test "a missing reason is a bad request" do
    post "/api/v1/trashes/#{@trash.id}/flags", headers: { "X-Device-Token" => create_device.token }

    assert_response :bad_request
  end

  test "only photos that are publicly visible can be flagged" do
    [create_trash, create_published_trash.tap(&:hide!)].each do |trash|
      assert_no_difference("Flag.count") { flag(trash: trash) }

      assert_response :not_found
    end
  end

  test "three people flagging a photo takes it off the public map" do
    2.times { flag }
    get "/api/v1/trashes/#{@trash.id}"
    assert_response :success

    flag

    get "/api/v1/trashes/#{@trash.id}"
    assert_response :not_found
    get "/api/v1/trashes", params: { lat: -15.7942, lng: -47.8825 }
    assert_empty response.parsed_body
  end
end
