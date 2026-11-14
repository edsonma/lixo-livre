require "test_helper"

class AuthenticateWithPasswordTest < ActiveSupport::TestCase
  def attempt(email:, password: PASSWORD, otp: nil)
    AuthenticateWithPassword.call(email: email, password: password, otp: otp)
  end

  test "the right email and password succeed, whatever the letter case of the email" do
    user = create_user(email: "ana@example.com")

    outcome = attempt(email: "ANA@Example.com")

    assert_predicate outcome, :success?
    assert_equal user, outcome.value
  end

  test "a wrong password and an unknown email fail in the same way" do
    create_user(email: "ana@example.com")

    assert_equal :invalid_credentials, attempt(email: "ana@example.com", password: "not-the-password").error
    assert_equal :invalid_credentials, attempt(email: "ghost@example.com").error
  end

  test "with two-factor on, the password alone is not enough" do
    user = create_user(email: "ana@example.com")
    secret = user.start_otp_setup!
    recovery_codes = user.enable_otp!(Totp.code(secret, Totp.step))

    assert_equal :otp_required, attempt(email: "ana@example.com").error
    assert_equal :otp_required, attempt(email: "ana@example.com", otp: "  ").error
    assert_equal :invalid_otp, attempt(email: "ana@example.com", otp: "not-a-code").error
    assert_predicate attempt(email: "ana@example.com", otp: recovery_codes.first), :success?
  end

  test "the second factor is only asked of someone who gave the right password" do
    user = create_user(email: "ana@example.com")
    user.enable_otp!(Totp.code(user.start_otp_setup!, Totp.step))

    assert_equal :invalid_credentials, attempt(email: "ana@example.com", password: "not-the-password").error
  end
end
