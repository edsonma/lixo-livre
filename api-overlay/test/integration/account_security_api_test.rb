require "test_helper"

class AccountSecurityApiTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  def json_post(path, body = {})
    post path, params: body.to_json, headers: { "Content-Type" => "application/json" }
  end

  def sent
    @sent ||= []
  end

  # Runs the block with email "configured" and captures what would be sent.
  def with_mail
    with_env("RESEND_API_KEY" => "re_test", "APP_ORIGIN" => "https://app.test") do
      Mailer.stub(:http_post, ->(_url, _headers, body) { sent << body; [200, "{}"] }) do
        perform_enqueued_jobs { yield }
      end
    end
  end

  def token_in(mail, name)
    mail[:text][/#{name}=([^\s]+)/, 1]
  end

  # --- email verification ---

  test "sign up sends a confirmation email, and the link confirms the address" do
    with_mail do
      json_post "/api/v1/users", { email: "new@example.com", password: "longenough1", accepted_terms: true }
    end
    assert_response :created
    assert_equal false, response.parsed_body.dig("user", "email_verified")
    assert_equal 1, sent.size
    assert_equal ["new@example.com"], sent.first[:to]

    json_post "/api/v1/email/verify", { token: token_in(sent.first, "verify") }
    assert_response :success
    assert_predicate User.find_by!(email: "new@example.com"), :email_verified?
  end

  test "a bad verification token is refused" do
    json_post "/api/v1/email/verify", { token: "nope" }
    assert_response :unprocessable_entity
  end

  test "reporting needs a confirmed email once mail is configured, and not before" do
    user = create_user(email_verified_at: nil)
    device = create_device(user: user)
    sign_in user
    upload = -> { post "/api/v1/trashes", params: { photo: uploaded_photo, lat: -15.79, lng: -47.88, taken_at: Time.current.iso8601 }, headers: { "X-Device-Token" => device.token } }

    with_env("RESEND_API_KEY" => "re_test") do
      upload.call
      assert_response :forbidden
      assert_equal "email_unverified", response.parsed_body["error"]
    end

    upload.call # no mail configured: the app does not insist
    assert_response :accepted
  end

  test "resend sends the confirmation again, only to a logged in person" do
    user = create_user(email_verified_at: nil)
    json_post "/api/v1/email/resend"
    assert_response :unauthorized

    sign_in user
    with_mail { json_post "/api/v1/email/resend" }
    assert_response :no_content
    assert_equal 1, sent.size
  end

  test "Google accounts are verified from the start" do
    GoogleIdentity.stub(:verify, GoogleIdentity::Identity.new(uid: "g1", email: "g@example.com", name: "G")) do
      json_post "/api/v1/session/google", { credential: "x", accepted_terms: true }
    end
    assert_predicate User.find_by!(email: "g@example.com"), :email_verified?
  end

  # --- password reset ---

  test "forgot always answers the same, and sends the email only for a real account" do
    user = create_user(email: "ana@example.com")
    with_mail do
      json_post "/api/v1/password/forgot", { email: "ANA@example.com" }
      assert_response :no_content
      json_post "/api/v1/password/forgot", { email: "nobody@example.com" }
      assert_response :no_content
    end
    assert_equal 1, sent.size
    assert_equal ["ana@example.com"], sent.first[:to]
    assert_includes sent.first[:subject], "senha"
    assert user.valid_password?(PASSWORD)
  end

  test "the reset link sets a new password once, and logs nobody in" do
    user = create_user(email: "ana@example.com")
    with_mail { json_post "/api/v1/password/forgot", { email: "ana@example.com" } }
    token = token_in(sent.first, "reset")

    json_post "/api/v1/password/reset", { token: token, password: "brand-new-pass" }
    assert_response :no_content
    assert user.reload.valid_password?("brand-new-pass")
    get "/api/v1/session"
    assert_nil response.parsed_body["user"]

    json_post "/api/v1/password/reset", { token: token, password: "another-pass-1" } # the link worked once
    assert_response :unprocessable_entity
    assert user.reload.valid_password?("brand-new-pass")
  end

  test "a reset needs a long enough password and a real token" do
    user = create_user
    token = user.generate_token_for(:password_reset)
    json_post "/api/v1/password/reset", { token: token, password: "short" }
    assert_response :unprocessable_entity
    assert user.reload.valid_password?(PASSWORD)

    json_post "/api/v1/password/reset", { token: "garbage", password: "longenough1" }
    assert_response :unprocessable_entity
  end

  test "the reset link expires" do
    user = create_user
    token = user.generate_token_for(:password_reset)
    travel 2.hours do
      json_post "/api/v1/password/reset", { token: token, password: "longenough1" }
      assert_response :unprocessable_entity
    end
  end

  # --- two-factor login ---

  def enable_two_factor(user)
    sign_in user
    json_post "/api/v1/two_factor/setup"
    secret = response.parsed_body["secret"]
    json_post "/api/v1/two_factor/enable", { code: Totp.code(secret, Totp.step) }
    [secret, response.parsed_body["recovery_codes"]]
  end

  test "setup then enable with a right code turns it on and returns recovery codes" do
    user = create_user
    sign_in user
    json_post "/api/v1/two_factor/setup"
    assert_response :success
    secret = response.parsed_body["secret"]
    assert_match(/\Aotpauth:\/\/totp\//, response.parsed_body["uri"])
    assert_not user.reload.otp_enabled?

    json_post "/api/v1/two_factor/enable", { code: "000000" }
    assert_response :unprocessable_entity

    json_post "/api/v1/two_factor/enable", { code: Totp.code(secret, Totp.step) }
    assert_response :success
    assert_equal User::RECOVERY_CODES, response.parsed_body["recovery_codes"].size
    assert_predicate user.reload, :otp_enabled?
    assert_equal true, response.parsed_body.dig("user", "two_factor")
    assert_not_equal secret, user.otp_secret # stored encrypted
  end

  test "with 2FA on, the password alone does not log in" do
    user = create_user(email: "ana@example.com")
    secret, = enable_two_factor(user)
    delete "/api/v1/session"

    json_post "/api/v1/session", { email: "ana@example.com", password: PASSWORD }
    assert_response :unauthorized
    assert_equal "otp_required", response.parsed_body["error"]

    json_post "/api/v1/session", { email: "ana@example.com", password: PASSWORD, otp: "000000" }
    assert_equal "invalid_otp", response.parsed_body["error"]

    json_post "/api/v1/session", { email: "ana@example.com", password: "wrong-password", otp: Totp.code(secret, Totp.step + 1) }
    assert_equal "invalid_credentials", response.parsed_body["error"]

    json_post "/api/v1/session", { email: "ana@example.com", password: PASSWORD, otp: Totp.code(secret, Totp.step + 1) }
    assert_response :success
  end

  test "a code works only once" do
    user = create_user(email: "ana@example.com")
    secret, = enable_two_factor(user) # used the code of the current step to enable
    delete "/api/v1/session"

    json_post "/api/v1/session", { email: "ana@example.com", password: PASSWORD, otp: Totp.code(secret, Totp.step) }
    assert_response :unauthorized # the same step was already used by /enable
  end

  test "a recovery code logs in once" do
    user = create_user(email: "ana@example.com")
    _secret, codes = enable_two_factor(user)
    delete "/api/v1/session"

    json_post "/api/v1/session", { email: "ana@example.com", password: PASSWORD, otp: codes.first }
    assert_response :success
    delete "/api/v1/session"
    json_post "/api/v1/session", { email: "ana@example.com", password: PASSWORD, otp: codes.first }
    assert_response :unauthorized
  end

  test "disabling needs a valid code" do
    user = create_user
    secret, codes = enable_two_factor(user)

    json_post "/api/v1/two_factor/disable", { code: "000000" }
    assert_response :unprocessable_entity
    assert_predicate user.reload, :otp_enabled?

    json_post "/api/v1/two_factor/disable", { code: codes.first }
    assert_response :success
    assert_not user.reload.otp_enabled?
    assert_nil user.otp_secret
  end

  test "two-factor endpoints need a login" do
    json_post "/api/v1/two_factor/setup"
    assert_response :unauthorized
  end
end
