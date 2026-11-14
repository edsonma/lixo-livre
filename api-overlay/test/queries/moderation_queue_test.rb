require "test_helper"

class ModerationQueueTest < ActiveSupport::TestCase
  test "held lists the reports waiting for a person, newest first" do
    older = create_trash(created_at: 2.days.ago).tap { |t| t.update_columns(ai_status: "needs_review") }
    newer = create_trash.tap { |t| t.update_columns(ai_status: "needs_review") }
    create_published_trash # not waiting for anyone

    assert_equal [newer, older], ModerationQueue.new.held.to_a
  end

  test "flagged lists published photos with a pending flag, once each" do
    flagged = create_published_trash
    2.times { Flag.create!(trash: flagged, device: create_device, reason: "privacy") }
    dismissed = create_published_trash.tap { |t| Flag.create!(trash: t, device: create_device, reason: "privacy", status: "dismissed") }
    create_published_trash # never flagged

    queue = ModerationQueue.new

    assert_equal [flagged], queue.flagged.to_a
    assert_not_includes queue.flagged, dismissed
  end
end
