require "test_helper"

class GoogleLoginTest < ActionDispatch::IntegrationTest
  Identity = GoogleIdentity::Identity

  def login_with(identity)
    GoogleIdentity.stub(:verify, identity) do
      post "/api/v1/session/google", params: { credential: "token" }.to_json, headers: { "Content-Type" => "application/json" }
    end
  end

  test "a first Google login creates the account and logs it in" do
    login_with(Identity.new(uid: "g-1", email: "new@example.com", name: "New Person"))

    assert_response :success
    user = User.find_by!(email: "new@example.com")
    assert_equal ["google", "g-1", "New Person"], [user.provider, user.uid, user.name]
    get "/api/v1/session"
    assert_equal user.id, response.parsed_body.dig("user", "id")
  end

  test "a returning Google login finds the same account" do
    login_with(Identity.new(uid: "g-1", email: "new@example.com", name: "New"))

    assert_no_difference("User.count") { login_with(Identity.new(uid: "g-1", email: "new@example.com", name: "New")) }
  end

  test "Google login for an email that already has an account links to it, keeping its history" do
    existing = create_user(email: "ana@example.com")

    assert_no_difference("User.count") { login_with(Identity.new(uid: "g-9", email: "ana@example.com", name: "Ana")) }

    assert_equal ["google", "g-9"], [existing.reload.provider, existing.uid]
  end

  test "an ADMIN_EMAILS address is an admin when it comes in through Google" do
    with_env("ADMIN_EMAILS" => "boss@example.com") do
      login_with(Identity.new(uid: "g-2", email: "boss@example.com", name: "Boss"))
    end

    assert_equal true, response.parsed_body.dig("user", "admin")
  end

  test "an invalid token is refused" do
    GoogleIdentity.stub(:verify, ->(_) { raise GoogleIdentity::Invalid, "bad" }) do
      post "/api/v1/session/google", params: { credential: "x" }.to_json, headers: { "Content-Type" => "application/json" }
    end

    assert_response :unauthorized
    assert_equal "invalid_google_token", response.parsed_body["error"]
  end

  test "without GOOGLE_CLIENT_ID the endpoint says so" do
    with_env("GOOGLE_CLIENT_ID" => nil) do
      post "/api/v1/session/google", params: { credential: "x" }.to_json, headers: { "Content-Type" => "application/json" }
    end

    assert_response :service_unavailable
    assert_equal "google_not_configured", response.parsed_body["error"]
  end
end
