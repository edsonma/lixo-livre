require "test_helper"

class OutcomeTest < ActiveSupport::TestCase
  test "a success carries its value and no error" do
    outcome = Outcome.success(:the_user)

    assert_predicate outcome, :success?
    assert_equal [:the_user, nil], [outcome.value, outcome.error]
  end

  test "a failure carries its error and no value" do
    outcome = Outcome.failure(:terms_required)

    assert_not outcome.success?
    assert_equal [nil, :terms_required], [outcome.value, outcome.error]
  end
end
