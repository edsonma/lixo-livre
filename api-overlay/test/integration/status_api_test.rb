require "test_helper"

class StatusApiTest < ActionDispatch::IntegrationTest
  test "reports demo mode, the map center and the counts" do
    create_published_trash
    with_env("DEMO_MODE" => "true", "DEMO_CENTER" => "-23.55,-46.63") do
      get "/api/v1/status"
    end

    assert_response :success
    body = response.parsed_body
    assert_equal "ok", body["status"]
    assert_equal true, body["demo_mode"]
    assert_equal({ "lat" => -23.55, "lng" => -46.63 }, body["center"])
    assert_equal 1, body["counts"]["reports"]
  end

  test "demo mode is off by default" do
    with_env("DEMO_MODE" => nil) { get "/api/v1/status" }

    assert_equal false, response.parsed_body["demo_mode"]
  end

  test "does not count reports that are not public" do
    create_trash

    get "/api/v1/status"

    assert_equal 0, response.parsed_body["counts"]["reports"]
  end
end
