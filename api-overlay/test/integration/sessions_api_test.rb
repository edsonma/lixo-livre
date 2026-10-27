require "test_helper"

class SessionsApiTest < ActionDispatch::IntegrationTest
  def json_post(path, body, headers = {})
    post path, params: body.to_json, headers: { "Content-Type" => "application/json" }.merge(headers)
  end

  def whoami
    get "/api/v1/session"
    response.parsed_body["user"]
  end

  # --- sign up ---

  test "signing up creates the account and logs it in" do
    json_post "/api/v1/users", { name: "Maria", email: "Maria@Example.com", password: "longenough1" }

    assert_response :created
    body = response.parsed_body["user"]
    assert_equal ["Maria", "maria@example.com", "user", false], body.values_at("name", "email", "role", "admin")
    assert_equal "maria@example.com", whoami["email"]
  end

  test "sign up needs a valid email, a password of at least 8 characters, and a free email" do
    json_post "/api/v1/users", { email: "not-an-email", password: "longenough1" }
    assert_response :unprocessable_entity

    json_post "/api/v1/users", { email: "a@example.com", password: "short" }
    assert_response :unprocessable_entity

    json_post "/api/v1/users", { email: "a@example.com" }
    assert_response :bad_request

    create_user(email: "taken@example.com")
    json_post "/api/v1/users", { email: "TAKEN@example.com", password: "longenough1" }
    assert_response :unprocessable_entity
  end

  test "the name defaults to the first part of the email" do
    json_post "/api/v1/users", { email: "zeca@example.com", password: "longenough1" }

    assert_equal "zeca", response.parsed_body.dig("user", "name")
  end

  # --- log in and out ---

  test "logging in with the right password, in any letter case" do
    user = create_user(email: "ana@example.com")

    json_post "/api/v1/session", { email: "ANA@example.com", password: PASSWORD }

    assert_response :success
    assert_equal user.id, whoami["id"]
    assert_not_nil user.reload.last_sign_in_at
  end

  test "a wrong password or unknown email is refused the same way" do
    create_user(email: "ana@example.com")

    json_post "/api/v1/session", { email: "ana@example.com", password: "wrong-password" }
    assert_response :unauthorized
    json_post "/api/v1/session", { email: "nobody@example.com", password: "whatever123" }
    assert_response :unauthorized
    assert_equal "invalid_credentials", response.parsed_body["error"]
    assert_nil whoami
  end

  test "an account without a password (Google, demo data) cannot be logged into with a blank one" do
    create_user(email: "g@example.com", password: nil)

    json_post "/api/v1/session", { email: "g@example.com", password: "" }

    assert_includes [400, 401], response.status
    assert_nil whoami
  end

  test "logging out ends the session" do
    create_user(email: "ana@example.com")
    json_post "/api/v1/session", { email: "ana@example.com", password: PASSWORD }

    delete "/api/v1/session"

    assert_response :no_content
    assert_nil whoami
  end

  test "nobody is logged in by default" do
    assert_nil whoami
  end

  # --- admin ---

  test "emails in ADMIN_EMAILS become admins when they sign up" do
    with_env("ADMIN_EMAILS" => "boss@example.com, other@example.com") do
      json_post "/api/v1/users", { email: "Boss@Example.com", password: "longenough1" }
    end

    assert_equal true, response.parsed_body.dig("user", "admin")
    assert_predicate User.find_by(email: "boss@example.com"), :admin?
  end

  test "an existing account is promoted at its next login once its email is listed" do
    user = create_user(email: "later@example.com")
    assert_not_predicate user, :admin?

    with_env("ADMIN_EMAILS" => "later@example.com") do
      json_post "/api/v1/session", { email: "later@example.com", password: PASSWORD }
    end

    assert_predicate user.reload, :admin?
  end

  test "other people are not admins" do
    with_env("ADMIN_EMAILS" => "boss@example.com") do
      json_post "/api/v1/users", { email: "someone@example.com", password: "longenough1" }
    end

    assert_equal false, response.parsed_body.dig("user", "admin")
  end

  # --- reporting needs login ---

  test "the reporting and my-reports endpoints refuse visitors" do
    device = create_device

    get "/api/v1/me/trashes", headers: { "X-Device-Token" => device.token }
    assert_response :unauthorized
    assert_equal "login_required", response.parsed_body["error"]

    post "/api/v1/me/trashes/1/publish", headers: { "X-Device-Token" => device.token }
    assert_response :unauthorized
  end

  # --- cross-site writes ---

  test "a write that comes from another site is refused, one from this site is not" do
    json_post "/api/v1/devices", {}, { "Origin" => "https://evil.example" }
    assert_response :forbidden
    assert_equal "cross_origin", response.parsed_body["error"]

    json_post "/api/v1/devices", {}, { "Origin" => "http://www.example.com" }
    assert_response :created

    json_post "/api/v1/devices", {} # no Origin: not a browser (the mobile app)
    assert_response :created
  end

  test "reads are never blocked by Origin" do
    get "/api/v1/status", headers: { "Origin" => "https://other.example" }

    assert_response :success
  end

  test "the status tells the page whether Google login is set up" do
    with_env("GOOGLE_CLIENT_ID" => "abc.apps.googleusercontent.com") { get "/api/v1/status" }
    assert_equal "abc.apps.googleusercontent.com", response.parsed_body.dig("auth", "google_client_id")

    with_env("GOOGLE_CLIENT_ID" => nil) { get "/api/v1/status" }
    assert_nil response.parsed_body.dig("auth", "google_client_id")
  end
end
