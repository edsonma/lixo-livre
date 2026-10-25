require "test_helper"

class DemoPlanTest < ActiveSupport::TestCase
  CENTER = [-15.7942, -47.8825].freeze
  NOW = Time.utc(2026, 10, 24, 12)

  def plan(count: 200, seed: 1)
    DemoPlan.generate(count: count, center: CENTER, now: NOW, seed: seed)
  end

  test "makes exactly the requested number of reports" do
    [0, 1, 7, 220].each { |n| assert_equal n, plan(count: n).size }
  end

  test "is deterministic for a seed and differs between seeds" do
    assert_equal plan(seed: 5), plan(seed: 5)
    assert_not_equal plan(seed: 5), plan(seed: 6)
  end

  test "stays inside the valid ranges" do
    plan.each do |report|
      assert_includes 1..5, report.severity
      assert_operator report.taken_at, :<=, NOW
      assert_operator report.taken_at, :>=, NOW - DemoPlan::MAX_AGE_DAYS.days
      assert_includes 0...DemoPlan::ACTORS, report.actor
      assert_match(/\Aseverity-#{report.severity}-[abc]\.jpg\z/, report.photo)
      assert_operator (report.lat - CENTER[0]).abs, :<, 0.5
      assert_operator (report.lng - CENTER[1]).abs, :<, 0.5
    end
  end

  test "every photo it names exists in db/demo_photos" do
    plan.map(&:photo).uniq.each do |name|
      assert Rails.root.join("db/demo_photos", name).exist?, "missing #{name}"
    end
  end

  test "clusters reports into hotspots rather than spreading them evenly" do
    cells = plan(count: 220).group_by { |r| [r.lat.round(2), r.lng.round(2)] }
    assert_operator cells.values.map(&:size).max, :>, 220 / cells.size * 2
  end
end
