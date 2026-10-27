require "test_helper"
require "webauthn/fake_client"

# Uses the webauthn gem's FakeClient as the "phone": it makes and signs credentials like a real
# authenticator would. The test host is www.example.com over http.
class PasskeysApiTest < ActionDispatch::IntegrationTest
  ORIGIN = "http://www.example.com".freeze
  RP_ID = "www.example.com".freeze

  setup do
    @user = create_user
    @phone = WebAuthn::FakeClient.new(ORIGIN)
  end

  def json_post(path, body = {})
    post path, params: body.to_json, headers: { "Content-Type" => "application/json" }
  end

  def add_passkey(user = @user)
    sign_in user
    json_post "/api/v1/passkeys/registration_options"
    assert_response :success
    credential = @phone.create(challenge: response.parsed_body["challenge"], rp_id: RP_ID, user_verified: true)
    json_post "/api/v1/passkeys", credential: credential, nickname: "My phone"
  end

  test "registration needs a login" do
    json_post "/api/v1/passkeys/registration_options"

    assert_response :unauthorized
  end

  test "a logged-in user can add a passkey, and it is listed" do
    add_passkey

    assert_response :created
    assert_equal 1, @user.passkeys.count
    assert_equal "My phone", @user.passkeys.first.nickname
    get "/api/v1/passkeys"
    assert_equal ["My phone"], response.parsed_body.map { |p| p["nickname"] }
  end

  test "the options ask for a resident key unlocked by fingerprint or face" do
    sign_in @user
    json_post "/api/v1/passkeys/registration_options"

    selection = response.parsed_body["authenticatorSelection"]
    assert_equal "required", selection["userVerification"]
    assert_equal "required", selection["residentKey"]
    assert_equal @user.reload.webauthn_id, response.parsed_body.dig("user", "id")
  end

  test "registration fails without a challenge from the server" do
    sign_in @user
    credential = @phone.create(challenge: SecureRandom.urlsafe_base64(32), rp_id: RP_ID, user_verified: true)

    json_post "/api/v1/passkeys", credential: credential

    assert_response :unprocessable_entity
    assert_equal 0, @user.passkeys.count
  end

  test "an answer signed for a different challenge is refused" do
    sign_in @user
    json_post "/api/v1/passkeys/registration_options"
    credential = @phone.create(challenge: SecureRandom.urlsafe_base64(32), rp_id: RP_ID, user_verified: true)

    json_post "/api/v1/passkeys", credential: credential

    assert_response :unprocessable_entity
    assert_equal 0, @user.passkeys.count
  end

  test "logging in with a passkey, no email needed" do
    add_passkey
    delete "/api/v1/session"
    assert_nil((get "/api/v1/session") && response.parsed_body["user"])

    json_post "/api/v1/passkeys/authentication_options"
    assert_response :success
    assertion = @phone.get(challenge: response.parsed_body["challenge"], rp_id: RP_ID, user_verified: true,
                           user_handle: @user.webauthn_id)
    json_post "/api/v1/passkeys/authenticate", credential: assertion

    assert_response :success
    assert_equal @user.id, response.parsed_body.dig("user", "id")
    get "/api/v1/session"
    assert_equal @user.id, response.parsed_body.dig("user", "id")
    assert_not_nil @user.passkeys.first.last_used_at
  end

  test "a challenge works once" do
    add_passkey
    delete "/api/v1/session"
    json_post "/api/v1/passkeys/authentication_options"
    assertion = @phone.get(challenge: response.parsed_body["challenge"], rp_id: RP_ID, user_verified: true)

    json_post "/api/v1/passkeys/authenticate", credential: assertion
    assert_response :success
    delete "/api/v1/session"
    json_post "/api/v1/passkeys/authenticate", credential: assertion

    assert_response :unprocessable_entity
  end

  test "an unknown passkey is refused" do
    other = WebAuthn::FakeClient.new(ORIGIN)
    json_post "/api/v1/passkeys/authentication_options"
    assertion = other.get(challenge: response.parsed_body["challenge"], rp_id: RP_ID, user_verified: true)

    json_post "/api/v1/passkeys/authenticate", credential: assertion

    assert_response :unauthorized
    get "/api/v1/session"
    assert_nil response.parsed_body["user"]
  end

  test "a passkey can be removed by its owner only" do
    add_passkey
    passkey = @user.passkeys.first

    sign_in create_user
    delete "/api/v1/passkeys/#{passkey.id}"
    assert_response :not_found
    assert Passkey.exists?(passkey.id)

    sign_in @user
    delete "/api/v1/passkeys/#{passkey.id}"
    assert_response :no_content
    assert_not Passkey.exists?(passkey.id)
  end
end
