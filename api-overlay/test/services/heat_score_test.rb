require "test_helper"

class HeatScoreTest < ActiveSupport::TestCase
  NOW = Time.utc(2026, 10, 27, 12)

  def row(severity, days_ago = 0, who: "u1", confidence: nil, kind: "dirty")
    HeatScore::Row.new(severity: severity, taken_at: NOW - days_ago.days, confidence: confidence, kind: kind, reporter: who)
  end

  def score(rows)
    HeatScore.call(rows, now: NOW)
  end

  test "a report loses half its weight every 14 days, and one from the future counts fully" do
    assert_in_delta 80, score([row(80)]).score, 1e-9
    assert_in_delta 40, score([row(80, 14)]).score, 1e-9
    assert_in_delta 50, score([row(50, -3)]).score, 1e-9
  end

  test "confidence of 0.8 or more counts fully, below that 60%, and an unknown one fully" do
    assert_in_delta 80, score([row(80, confidence: 0.8)]).score, 1e-9
    assert_in_delta 80, score([row(80, confidence: 0.99)]).score, 1e-9
    assert_in_delta 48, score([row(80, confidence: 0.7)]).score, 1e-9
    assert_in_delta 80, score([row(80, confidence: nil)]).score, 1e-9
  end

  test "one person counts once a day: only their heaviest report is used" do
    result = score([row(80), row(60), row(30)])

    assert_in_delta 80, result.score, 1e-9
    assert_equal 3, result.count
  end

  test "the same person on another day counts again" do
    assert_in_delta 80 + 60 * 0.5**(1.0 / 14), score([row(80), row(60, 1)]).score, 1e-9
  end

  test "different people confirming each other add 15% each, up to 45%" do
    assert_in_delta 120 * 1.15, score([row(80, who: "a"), row(40, who: "b")]).score, 1e-9
    assert_in_delta 100 * 1.45, score((1..10).map { |i| row(10, who: "p#{i}") }).score, 1e-9
  end

  test "a cleanup wipes the reports before it" do
    result = score([row(80, 5, who: "a"), row(70, 3, who: "b"), row(5, 1, who: "c", kind: "cleanup")])

    assert_in_delta 0, result.score, 1e-9
    assert_equal NOW - 1.day, result.cleaned_at
    assert_equal 3, result.count
  end

  test "reports after the latest cleanup count again" do
    result = score([row(80, 5), row(5, 3, who: "c", kind: "cleanup"), row(60, 1, who: "d")])

    assert_in_delta 60 * 0.5**(1.0 / 14), result.score, 1e-9
  end

  test "an empty cell scores zero" do
    result = score([])

    assert_equal [0, 0, nil], [result.score, result.count, result.cleaned_at]
  end
end
