require "test_helper"

class RegisterAccountTest < ActiveSupport::TestCase
  def register(**overrides)
    RegisterAccount.call(**{ email: "ana@example.com", password: "longenough1", accepted_terms: true }.merge(overrides))
  end

  test "creates the account with the terms accepted and the name given" do
    outcome = register(name: "  Ana  ")

    assert_predicate outcome, :success?
    assert_equal ["Ana", "ana@example.com", true], [outcome.value.name, outcome.value.email, outcome.value.terms_current?]
  end

  test "without accepting the terms nothing is created" do
    assert_no_difference("User.count") do
      assert_equal :terms_required, register(accepted_terms: nil).error
      assert_equal :terms_required, register(accepted_terms: "false").error
    end
  end

  test "an invalid account raises, for the controller to answer" do
    assert_raises(ActiveRecord::RecordInvalid) { register(email: "not-an-email") }
  end

  test "the confirmation email is sent only when email delivery is configured" do
    with_env("RESEND_API_KEY" => "re_test") do
      assert_enqueued_with(job: SendUserEmailJob) { register }
    end
    with_env("RESEND_API_KEY" => nil) do
      assert_no_enqueued_jobs(only: SendUserEmailJob) { register(email: "bia@example.com") }
    end
  end
end
