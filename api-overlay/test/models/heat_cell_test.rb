require "test_helper"

class HeatCellTest < ActiveSupport::TestCase
  NOW = Time.utc(2026, 10, 24, 12)

  def cell_for(trash)
    HeatCell.find_or_initialize_by(h3_index: trash.h3_index, resolution: Trash::H3_RESOLUTION)
  end

  test "a report loses half its weight every 14 days" do
    assert_in_delta 4.0, HeatCell.weight(4, NOW, now: NOW), 1e-9
    assert_in_delta 2.0, HeatCell.weight(4, NOW - 14.days, now: NOW), 1e-9
    assert_in_delta 1.0, HeatCell.weight(4, NOW - 28.days, now: NOW), 1e-9
    assert_in_delta 4 * 0.5**0.5, HeatCell.weight(4, NOW - 7.days, now: NOW), 1e-9
  end

  test "a report from the future counts fully, never more" do
    assert_in_delta 5.0, HeatCell.weight(5, NOW + 3.days, now: NOW), 1e-9
  end

  test "recompute! adds up the published reports in the cell" do
    a = create_published_trash(severity: 80)
    create_published_trash(severity: 40)
    create_published_trash(severity: 100).hide!                                         # hidden
    create_trash                                                                      # pending
    create_published_trash(severity: 100, lat: -15.7492)                                # another cell, 5 km away

    cell = cell_for(a)
    cell.recompute!

    assert_predicate cell, :persisted?
    assert_equal 2, cell.reports_count
    assert_in_delta 120.0 * 1.15, cell.score, 3 # 80 + 40, two different people confirm each other (+15%), a little decay
    assert_equal Trash::H3_RESOLUTION, cell.resolution
    assert_not_nil cell.computed_at
  end

  test "recompute! puts the cell center close to its reports" do
    trash = create_published_trash
    cell = cell_for(trash)
    cell.recompute!

    assert_operator Geo.distance_m(cell.lonlat.y, cell.lonlat.x, -15.7942, -47.8825), :<, 200 # resolution 9 cells are ~170 m
  end

  test "recompute! drops the score to zero when nothing is left in the cell" do
    trash = create_published_trash
    cell = cell_for(trash)
    cell.recompute!
    trash.hide!

    cell.recompute!

    assert_equal 0, cell.score
    assert_equal 0, cell.reports_count
  end

  test "scores decay on their own as time passes" do
    trash = create_published_trash(severity: 80, taken_at: Time.current)
    cell = cell_for(trash)
    cell.recompute!
    fresh = cell.score

    travel_to 14.days.from_now do
      cell.recompute!
    end

    assert_in_delta fresh / 2, cell.score, 1
  end

  test "in_bbox returns only cells inside the box" do
    inside = HeatCell.create!(h3_index: "a", resolution: 9, lonlat: Trash.point(-47.88, -15.79), score: 3)
    HeatCell.create!(h3_index: "b", resolution: 9, lonlat: Trash.point(-46.63, -23.55), score: 3) # Sao Paulo

    assert_equal [inside.id], HeatCell.in_bbox(-48.0, -16.0, -47.7, -15.6).pluck(:id)
  end

  test "an H3 cell exists once per resolution" do
    HeatCell.create!(h3_index: "a", resolution: 9, lonlat: Trash.point(1, 1))

    assert_not HeatCell.new(h3_index: "a", resolution: 9, lonlat: Trash.point(1, 1)).valid?
    assert HeatCell.new(h3_index: "a", resolution: 8, lonlat: Trash.point(1, 1)).valid?
  end

  test "to_feature is a GeoJSON point with the score" do
    cell = HeatCell.create!(h3_index: "abc", resolution: 9, lonlat: Trash.point(-47.88, -15.79), score: 3.14159, reports_count: 2)

    feature = cell.to_feature

    assert_equal "Feature", feature[:type]
    assert_equal({ h3: "abc", score: 3.14, count: 2 }, feature[:properties])
    assert_equal "Point", feature[:geometry][:type]
    assert_in_delta(-47.88, feature[:geometry][:coordinates][0], 1e-6) # longitude first
    assert_in_delta(-15.79, feature[:geometry][:coordinates][1], 1e-6)
  end

  # --- the scoring rules (the arithmetic itself is in test/services/heat_score_test.rb) ---

  test "a cleanup erases the reports before it and the cell remembers when" do
    dirty = create_published_trash(severity: 80, taken_at: 3.days.ago)
    clean = create_published_trash(severity: 0, taken_at: 1.day.ago, kind: "cleanup")
    cell = cell_for(dirty)

    cell.recompute!

    assert_in_delta 0, cell.score, 0.01
    assert_equal 2, cell.reports_count
    assert_in_delta clean.taken_at.to_f, cell.cleaned_at.to_f, 1
  end

  test "a report made after the cleanup counts again" do
    create_published_trash(severity: 80, taken_at: 3.days.ago)
    create_published_trash(severity: 0, taken_at: 2.days.ago, kind: "cleanup")
    after = create_published_trash(severity: 60, taken_at: 1.hour.ago)
    cell = cell_for(after)

    cell.recompute!

    assert_in_delta 60, cell.score, 2
  end

  test "reports the AI was only fairly sure about weigh less" do
    sure = create_published_trash(severity: 50, ai_confidence: 0.9)
    unsure = create_published_trash(severity: 50, ai_confidence: 0.7, lat: -15.7492)

    a = cell_for(sure).tap(&:recompute!)
    b = cell_for(unsure).tap(&:recompute!)

    assert_in_delta 50, a.score, 1
    assert_in_delta 30, b.score, 1
  end

  test "one person's repeated photos on the same day count once" do
    user = create_user
    device = create_device(user: user)
    first = create_published_trash(severity: 80, device: device, user: user)
    create_published_trash(severity: 60, device: device, user: user)
    create_published_trash(severity: 40, device: device, user: user)
    cell = cell_for(first)

    cell.recompute!

    assert_equal 3, cell.reports_count
    assert_in_delta 80, cell.score, 2
  end
end
