require "test_helper"

class DevicesApiTest < ActionDispatch::IntegrationTest
  test "POST /devices creates an anonymous device and returns its token" do
    assert_difference("Device.count", 1) { post "/api/v1/devices" }

    assert_response :created
    token = response.parsed_body["token"]
    assert_equal 24, token.length
    assert_nil Device.find_by!(token: token).user
  end

  test "every device gets its own token" do
    post "/api/v1/devices"
    first = response.parsed_body["token"]
    post "/api/v1/devices"

    assert_not_equal first, response.parsed_body["token"]
  end
end
