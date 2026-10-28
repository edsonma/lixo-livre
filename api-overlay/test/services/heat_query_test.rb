require "test_helper"

class HeatQueryTest < ActiveSupport::TestCase
  NOW = Time.utc(2026, 10, 27, 12)

  def row(severity, days_ago, kind: "dirty", reporter: "u1")
    HeatScore::Row.new(severity: severity, taken_at: NOW - days_ago * 86_400, confidence: 0.9, kind: kind, reporter: reporter)
  end

  test "a place that got a fresh bad report is getting worse" do
    rows = [row(30, 20), row(90, 1)]
    trend = HeatQuery.trend(rows, now: NOW)
    assert_equal "worse", trend[:label]
    assert_operator trend[:delta], :>=, HeatQuery::TREND_THRESHOLD
  end

  test "a place whose old report is fading and has no new one is getting better" do
    trend = HeatQuery.trend([row(90, 15)], now: NOW)
    assert_equal "better", trend[:label]
  end

  test "a cleanup makes it better" do
    trend = HeatQuery.trend([row(80, 20), row(5, 1, kind: "cleanup")], now: NOW)
    assert_equal "better", trend[:label]
  end

  test "an old, faded report is stable" do
    assert_equal "stable", HeatQuery.trend([row(40, 80)], now: NOW)[:label]
  end

  test "regions are ranked by the average score of their dirty cells" do
    mk = ->(h3, score, delta, cleaned: nil) {
      HeatQuery::Cell.new(h3: h3, lat: 0, lng: 0, score: score, count: 1, cleaned_at: cleaned,
                          trend: { delta: delta, label: "stable" })
    }
    cells = [mk.("a1", 80, 10), mk.("a2", 60, 0), mk.("b1", 30, -10), mk.("c1", 1, 0, cleaned: NOW)]
    parents = { "a1" => "A", "a2" => "A", "b1" => "B", "c1" => "C" }
    H3.stub(:to_geo_coordinates, [1.0, 2.0]) do
      H3.stub(:from_string, ->(s) { s }) do
        regions = HeatQuery.regions(cells, parent_of: ->(h3) { parents[h3] })
        assert_equal %w[A B], regions.map { |r| r[:region] } # C is only cleaned cells
        assert_equal 70.0, regions.first[:score]
        assert_equal 2, regions.first[:cells]
        assert_equal "worse", regions.first[:trend][:label]
      end
    end
  end
end
