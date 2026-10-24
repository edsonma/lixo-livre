require "test_helper"

class HeatCellJobsTest < ActiveSupport::TestCase
  test "RefreshHeatCellJob creates the cell and scores it" do
    trash = create_published_trash(severity: 4)

    assert_difference("HeatCell.count", 1) { RefreshHeatCellJob.perform_now(trash.h3_index) }

    cell = HeatCell.find_by!(h3_index: trash.h3_index, resolution: Trash::H3_RESOLUTION)
    assert_equal 1, cell.reports_count
    assert_in_delta 4.0, cell.score, 0.1
    assert_not_nil cell.lonlat
  end

  test "RefreshHeatCellJob updates an existing cell instead of adding another" do
    trash = create_published_trash(severity: 4)
    RefreshHeatCellJob.perform_now(trash.h3_index)
    create_published_trash(severity: 2)

    assert_no_difference("HeatCell.count") { RefreshHeatCellJob.perform_now(trash.h3_index) }

    assert_equal 2, HeatCell.find_by!(h3_index: trash.h3_index).reports_count
  end

  test "RefreshHeatCellJob leaves hidden and unvalidated reports out" do
    shown = create_published_trash(severity: 3)
    create_published_trash(severity: 5).hide!
    create_trash

    RefreshHeatCellJob.perform_now(shown.h3_index)

    cell = HeatCell.find_by!(h3_index: shown.h3_index)
    assert_equal 1, cell.reports_count
    assert_in_delta 3.0, cell.score, 0.1
  end

  test "RecomputeHeatCellsJob applies time decay to every cell, even without new reports" do
    here = create_published_trash(severity: 4, taken_at: Time.current)
    there = create_published_trash(severity: 2, taken_at: Time.current, lat: -15.7492)
    [here, there].each { |t| RefreshHeatCellJob.perform_now(t.h3_index) }

    travel_to 14.days.from_now do
      RecomputeHeatCellsJob.perform_now
    end

    assert_in_delta 2.0, HeatCell.find_by!(h3_index: here.h3_index).score, 0.05
    assert_in_delta 1.0, HeatCell.find_by!(h3_index: there.h3_index).score, 0.05
  end

  test "RecomputeHeatCellsJob zeroes a cell whose reports were all hidden" do
    trash = create_published_trash(severity: 4)
    RefreshHeatCellJob.perform_now(trash.h3_index)
    trash.hide!

    RecomputeHeatCellsJob.perform_now

    assert_equal 0, HeatCell.find_by!(h3_index: trash.h3_index).score
  end
end
