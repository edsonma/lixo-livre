require "test_helper"

class FollowAlertsTest < ActiveSupport::TestCase
  test "decide: a rise of 15 points or more is worse" do
    assert_equal :worse, FollowAlerts.decide(last_score: 30, last_cleaned_at: nil, score: 45, cleaned_at: nil)
    assert_nil FollowAlerts.decide(last_score: 30, last_cleaned_at: nil, score: 44, cleaned_at: nil)
  end

  test "decide: a new cleanup is announced once" do
    now = Time.current
    assert_equal :cleaned, FollowAlerts.decide(last_score: 60, last_cleaned_at: nil, score: 0, cleaned_at: now)
    assert_nil FollowAlerts.decide(last_score: 0, last_cleaned_at: now, score: 0, cleaned_at: now)
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
end
