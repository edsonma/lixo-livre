require "test_helper"

class PlaceHistoryTest < ActiveSupport::TestCase
  def at(year, month, day = 15) = Time.utc(year, month, day, 12)

  test "one point per month, with the average severity and the number of reports" do
    rows = [[80, at(2026, 9)], [40, at(2026, 9, 20)], [20, at(2026, 10)]]

    assert_equal [{ month: "2026-09", average: 60, reports: 2 }, { month: "2026-10", average: 20, reports: 1 }],
                 PlaceHistory.monthly(rows)
  end

  test "oldest month first, whatever order the rows come in" do
    rows = [[10, at(2026, 10)], [90, at(2026, 6)], [50, at(2026, 8)]]
    assert_equal %w[2026-06 2026-08 2026-10], PlaceHistory.monthly(rows).map { |p| p[:month] }
  end

  test "keeps only the latest six months" do
    rows = (1..9).map { |m| [m * 10, at(2026, m)] }
    months = PlaceHistory.monthly(rows).map { |p| p[:month] }
    assert_equal %w[2026-04 2026-05 2026-06 2026-07 2026-08 2026-09], months
  end

  test "the average is rounded, and an empty place has no history" do
    assert_equal 33, PlaceHistory.monthly([[10, at(2026, 9)], [10, at(2026, 9)], [80, at(2026, 9)]]).first[:average]
    assert_equal [], PlaceHistory.monthly([])
  end

  test "months are counted in UTC, so a report at midnight local time lands in the right month" do
    late = Time.new(2026, 9, 30, 23, 30, 0, "-03:00") # already October in UTC
    assert_equal "2026-10", PlaceHistory.monthly([[50, late]]).first[:month]
  end

  test "the months argument limits the points" do
    rows = (1..4).map { |m| [50, at(2026, m)] }
    assert_equal 2, PlaceHistory.monthly(rows, months: 2).size
  end
end
