require "test_helper"

class FollowAlertsTest < ActiveSupport::TestCase
  test "decide: a rise of 15 points or more is worse" do
    assert_equal :worse, Messaging::FollowAlerts.decide(last_score: 30, last_cleaned_at: nil, score: 45, cleaned_at: nil)
    assert_nil Messaging::FollowAlerts.decide(last_score: 30, last_cleaned_at: nil, score: 44, cleaned_at: nil)
  end

  test "decide: a new cleanup is announced once" do
    now = Time.current
    assert_equal :cleaned, Messaging::FollowAlerts.decide(last_score: 60, last_cleaned_at: nil, score: 0, cleaned_at: now)
    assert_nil Messaging::FollowAlerts.decide(last_score: 0, last_cleaned_at: now, score: 0, cleaned_at: now)
  end

  test "run notifies followers of a cell that got worse and remembers the new score" do
    trash = create_published_trash(severity: 20)
    RefreshHeatCellJob.perform_now(trash.h3_index)
    follower = create_user
    Follow.start(follower, trash.h3_index)
    other = create_user # does not follow

    create_published_trash(severity: 90)
    assert_difference -> { follower.notifications.count }, 1 do
      RefreshHeatCellJob.perform_now(trash.h3_index)
    end

    note = follower.notifications.last
    assert_equal "worse", note.kind
    assert_equal trash.h3_index, note.h3_index
    assert_operator note.score, :>, note.previous_score
    assert_equal 0, other.notifications.count
    assert_in_delta HeatCell.find_by!(h3_index: trash.h3_index).score, follower.follows.first.last_score, 0.01

    assert_no_difference -> { follower.notifications.count } do
      RefreshHeatCellJob.perform_now(trash.h3_index) # nothing changed
    end
  end

  test "run notifies when the place is cleaned" do
    trash = create_published_trash(severity: 80)
    RefreshHeatCellJob.perform_now(trash.h3_index)
    follower = create_user
    Follow.start(follower, trash.h3_index)

    cleanup = create_published_trash(severity: 3, taken_at: Time.current)
    cleanup.update_columns(kind: "cleanup")
    RefreshHeatCellJob.perform_now(trash.h3_index)

    assert_equal ["cleaned"], follower.notifications.pluck(:kind)
  end

  test "retract takes back the alert of a report that was removed, and keeps the ones other reports still justify" do
    trash = create_published_trash(severity: 10)
    RefreshHeatCellJob.perform_now(trash.h3_index)
    follower = create_user
    Follow.start(follower, trash.h3_index)
    big = create_published_trash(severity: 90)
    RefreshHeatCellJob.perform_now(trash.h3_index)
    assert_equal 1, follower.notifications.where(kind: "worse").count

    big.destroy!
    RetractAlertsJob.perform_now(trash.h3_index, big.published_at.iso8601(6))

    assert_equal 0, follower.notifications.where(kind: "worse").count
  end

  test "retract leaves an alert alone when the place is still that bad" do
    trash = create_published_trash(severity: 10)
    RefreshHeatCellJob.perform_now(trash.h3_index)
    follower = create_user
    Follow.start(follower, trash.h3_index)
    create_published_trash(severity: 90)
    create_published_trash(severity: 85)
    RefreshHeatCellJob.perform_now(trash.h3_index)

    cell = HeatCell.find_by!(h3_index: trash.h3_index)
    assert_equal 0, Messaging::FollowAlerts.retract(cell, since: 1.hour.ago)
    assert_equal 1, follower.notifications.where(kind: "worse").count
  end

  test "retract only looks at alerts made after the removed report was published" do
    trash = create_published_trash(severity: 10)
    RefreshHeatCellJob.perform_now(trash.h3_index)
    follower = create_user
    Follow.start(follower, trash.h3_index)
    create_published_trash(severity: 90)
    RefreshHeatCellJob.perform_now(trash.h3_index)
    cell = HeatCell.find_by!(h3_index: trash.h3_index)
    cell.update_columns(score: 0)

    assert_equal 0, Messaging::FollowAlerts.retract(cell, since: 1.hour.from_now)
    assert_equal 1, follower.notifications.count
  end
end
