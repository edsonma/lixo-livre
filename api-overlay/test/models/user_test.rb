require "test_helper"

class UserTest < ActiveSupport::TestCase
  test "an account needs no password (Google accounts, demo data) but a given one must be long enough" do
    assert User.new(email: "a@example.com").valid?
    assert_not User.new(email: "a@example.com", password: "short").valid?
    assert User.new(email: "a@example.com", password: "long enough").valid?
  end

  test "emails are unique whatever their letter case" do
    create_user(email: "ana@example.com")

    assert_not User.new(email: "ANA@example.com").valid?
  end

  test "the name defaults to the start of the email and every account gets a passkey handle" do
    user = User.create!(email: "zeca@example.com")

    assert_equal "zeca", user.name
    assert_predicate user.webauthn_id, :present?
  end

  test "ADMIN_EMAILS makes listed addresses admins, ignoring case and spaces" do
    with_env("ADMIN_EMAILS" => " Boss@example.com ,other@example.com") do
      assert_predicate User.create!(email: "boss@example.com"), :admin?
      assert_not_predicate User.create!(email: "nobody@example.com"), :admin?
    end
  end

  test "the demo seeder's accounts still work without passwords" do
    assert_nothing_raised { DemoSeeder.call(count: 5) }
  end
  test "with email delivery on, a listed address is not an admin until it has confirmed the email" do
    with_env("ADMIN_EMAILS" => "boss@example.com", "RESEND_API_KEY" => "re_test") do
      boss = User.create!(email: "boss@example.com") # anyone can type any address at sign-up
      assert_not_predicate boss, :admin?

      boss.verify_email!

      assert_predicate boss.reload, :admin?
    end
  end

  test "with email delivery on, a listed address that is already verified (Google) is an admin at once" do
    with_env("ADMIN_EMAILS" => "boss@example.com", "RESEND_API_KEY" => "re_test") do
      assert_predicate User.create!(email: "boss@example.com", email_verified_at: Time.current), :admin?
    end
  end

  test "a very long name is cut to 100 characters, whether given or taken from the email" do
    assert_equal 100, User.create!(email: "a@example.com", name: "x" * 500).name.length
    assert_equal 100, User.create!(email: "#{'y' * 150}@example.com").name.length
  end

  test "checking a password for an account that does not exist always says no" do
    assert_equal false, User.fake_password_check("whatever")
    assert_equal false, User.fake_password_check(nil)
  end

  test "reset_credentials! leaves no old way in: password, passkeys and second factor are gone" do
    user = create_user(email_verified_at: nil)
    user.passkeys.create!(external_id: "cred-1", public_key: "pk")
    secret = user.start_otp_setup!
    user.enable_otp!(Totp.code(secret, Totp.step))
    assert_predicate user, :otp_enabled?

    user.reset_credentials!

    user.reload
    assert_not user.valid_password?(PASSWORD)
    assert_empty user.passkeys
    assert_not_predicate user, :otp_enabled?
  end
  test "promote_if_eligible! makes an existing account admin once its address is listed" do
    user = create_user(email: "later@example.com")
    assert_not_predicate user, :admin?

    with_env("ADMIN_EMAILS" => "later@example.com") { user.promote_if_eligible! }

    assert_predicate user.reload, :admin?
  end

  test "reset_password! sets the password and counts as proof of the inbox" do
    user = create_user(email_verified_at: nil)

    user.reset_password!("a-new-password")

    assert user.reload.valid_password?("a-new-password")
    assert_predicate user, :email_verified?
  end
end
