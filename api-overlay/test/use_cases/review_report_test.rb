require "test_helper"

class ReviewReportTest < ActiveSupport::TestCase
  setup { @moderator = create_user(role: :moderator) }

  def review(trash) = ReviewReport.new(trash, reviewer: @moderator)

  # A report the pipeline held: protected photo, no verdict.
  def held_trash
    create_trash.tap { |t| t.update_columns(ai_status: "needs_review", ai_payload: { "reason" => "metadata_mismatch" }, sanitized_at: Time.current) }
  end

  def flagged_trash
    create_published_trash.tap { |t| Flag.create!(trash: t, device: create_device, reason: "privacy") }
  end

  # --- held reports ---

  test "approving a held report publishes it with the chosen severity (a number or its text) and types" do
    trash = review(held_trash).approve(severity: "70", types: %w[plastic glass])

    assert_equal [70, %w[plastic glass], true, "validated"], [trash.severity, trash.trash_types, trash.published?, trash.ai_status]
    assert_equal @moderator.id, trash.ai_payload["reviewer_id"]
  end

  test "approving a held report needs a whole-number severity" do
    held = held_trash

    assert_raises(ReviewReport::SeverityMissing) { review(held).approve }
    assert_raises(ReviewReport::SeverityMissing) { review(held).approve(severity: "") }
    assert_raises(ReviewReport::SeverityInvalid) { review(held).approve(severity: "lots") }
    assert_raises(ActiveRecord::RecordInvalid) { review(held).approve(severity: 150) } # the model knows the range
    assert_predicate held.reload, :needs_review?
  end

  test "rejecting a held report rejects it and deletes its photo" do
    trash = held_trash

    assert_enqueued_with(job: ActiveStorage::PurgeJob) { review(trash).reject }

    assert_predicate trash.reload, :rejected?
  end

  # --- flagged photos ---

  test "approving a flagged photo keeps it: the flags are dismissed and no severity is asked" do
    trash = review(flagged_trash).approve

    assert_equal ["dismissed"], trash.flags.map(&:status)
    assert_nil trash.hidden_at
  end

  test "rejecting a flagged photo takes it down: the flags are resolved" do
    trash = review(flagged_trash).reject

    assert_equal ["resolved"], trash.flags.map(&:status)
    assert_not_nil trash.hidden_at
  end

  test "a report in neither queue cannot be reviewed" do
    published = create_published_trash

    assert_raises(Trash::NotReviewable) { review(published).approve }
    assert_raises(Trash::NotReviewable) { review(published).reject }
  end
end
