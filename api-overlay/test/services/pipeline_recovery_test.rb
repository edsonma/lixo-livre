require "test_helper"

class PipelineRecoveryTest < ActiveSupport::TestCase
  test "re-queues old reports that were never sanitized" do
    trash = create_trash
    clear_enqueued_jobs

    result = PipelineRecovery.requeue_stuck(now: 1.hour.from_now)

    assert_equal({ sanitize: 1, validate: 0 }, result)
    assert_enqueued_with(job: SanitizePhotoJob, args: [trash.id])
  end

  test "purges drafts nobody published for a week, and nothing else" do
    stale = create_draft_trash.tap { |t| t.update_columns(validated_at: 8.days.ago) }
    fresh = create_draft_trash.tap { |t| t.update_columns(validated_at: 2.days.ago) }
    published = create_published_trash.tap { |t| t.update_columns(validated_at: 30.days.ago) }
    pending_report = create_trash.tap { |t| t.update_columns(created_at: 30.days.ago) }

    assert_equal 1, PipelineRecovery.purge_stale_drafts

    assert_not Trash.exists?(stale.id)
    assert Trash.exists?(fresh.id)
    assert Trash.exists?(published.id), "a published report is never purged"
    assert Trash.exists?(pending_report.id), "a report still in the pipeline is not a draft"
  end

  test "re-queues sanitized reports that were never validated" do
    trash = create_trash
    trash.update_columns(sanitized_at: Time.current)
    clear_enqueued_jobs

    result = PipelineRecovery.requeue_stuck(now: 1.hour.from_now)

    assert_equal({ sanitize: 0, validate: 1 }, result)
    assert_enqueued_with(job: ValidateTrashJob, args: [trash.id])
  end

  test "leaves recent reports alone, they may still be in progress" do
    create_trash
    clear_enqueued_jobs

    assert_equal({ sanitize: 0, validate: 0 }, PipelineRecovery.requeue_stuck)
    assert_no_enqueued_jobs
  end

  test "ignores reports that are finished, held for review or hidden" do
    create_published_trash
    create_trash.tap { |t| t.update_columns(ai_status: "needs_review") }
    clear_enqueued_jobs

    assert_equal({ sanitize: 0, validate: 0 }, PipelineRecovery.requeue_stuck(now: 1.day.from_now))
  end
end
