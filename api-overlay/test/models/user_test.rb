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
end
