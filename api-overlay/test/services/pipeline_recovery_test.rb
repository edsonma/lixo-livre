require "test_helper"

class PipelineRecoveryTest < ActiveSupport::TestCase
  test "re-queues old reports that were never sanitized" do
    trash = create_trash
    clear_enqueued_jobs

    result = PipelineRecovery.requeue_stuck(now: 1.hour.from_now)

    assert_equal({ sanitize: 1, validate: 0 }, result)
    assert_enqueued_with(job: SanitizePhotoJob, args: [trash.id])
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
