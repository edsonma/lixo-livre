require "test_helper"

class ValidateTrashJobTest < ActiveSupport::TestCase
  setup do
    @vision_calls = 0
    TrashVision.provider = lambda { |_photo|
      @vision_calls += 1
      @vision_answer || vision_result
    }
  end

  # A report that SanitizePhotoJob has already finished with.
  def sanitized_trash(**attrs)
    create_trash(**attrs).tap { |t| t.update_columns(sanitized_at: Time.current) }
  end

  test "validates a trash photo: severity, types and confidence come from the AI" do
    @vision_answer = vision_result(severity: 95, types: %w[plastic bulky_items], confidence: 0.88)
    trash = sanitized_trash

    ValidateTrashJob.perform_now(trash.id)

    trash.reload
    assert_predicate trash, :validated?
    assert_equal 95, trash.severity
    assert_equal %w[plastic bulky_items], trash.trash_types
    assert_in_delta 0.88, trash.ai_confidence
    assert_not_nil trash.validated_at
  end

  test "a validated report goes to the map right away: the AI's score is the approval" do
    trash = sanitized_trash

    ValidateTrashJob.perform_now(trash.id)

    assert_not_nil trash.reload.published_at
    assert_includes Trash.for_heatmap.pluck(:id), trash.id
  end

  test "AUTO_PUBLISH=false brings back the manual step: validated reports wait for their author" do
    trash = sanitized_trash

    with_env("AUTO_PUBLISH" => "false") { ValidateTrashJob.perform_now(trash.id) }

    trash.reload
    assert_predicate trash, :validated?
    assert_nil trash.published_at
    assert_predicate trash, :publishable?
    assert_not_includes Trash.for_heatmap.pluck(:id), trash.id
  end

  test "validating re-scores the heat cell" do
    trash = sanitized_trash

    assert_enqueued_with(job: RefreshHeatCellJob, args: [trash.h3_index]) { ValidateTrashJob.perform_now(trash.id) }
  end

  test "rejects photos that are not trash" do
    @vision_answer = vision_result(is_trash: false, severity: nil, types: [], confidence: 0.99, raw: { "why" => "a cat" })
    trash = sanitized_trash

    ValidateTrashJob.perform_now(trash.id)

    trash.reload
    assert_predicate trash, :rejected?
    assert_nil trash.severity
    assert_equal({ "why" => "a cat" }, trash.ai_payload)
    assert_not_includes Trash.for_heatmap.pluck(:id), trash.id
  end

  test "sends low-confidence answers to human review without a severity" do
    @vision_answer = vision_result(confidence: 0.4)
    trash = sanitized_trash

    ValidateTrashJob.perform_now(trash.id)

    trash.reload
    assert_predicate trash, :needs_review?
    assert_nil trash.severity
    assert_in_delta 0.4, trash.ai_confidence
  end

  test "the confidence threshold itself is accepted" do
    @vision_answer = vision_result(confidence: ValidateTrashJob::CONFIDENCE_THRESHOLD)
    trash = sanitized_trash

    ValidateTrashJob.perform_now(trash.id)

    assert_predicate trash.reload, :validated?
  end

  test "never looks at a photo that has not been sanitized" do
    trash = create_trash # sanitized_at is nil

    ValidateTrashJob.perform_now(trash.id)

    assert_equal 0, @vision_calls
    assert_predicate trash.reload, :pending?
  end

  test "sends reports whose EXIF contradicts the claim to review, without paying for the AI" do
    trash = sanitized_trash
    trash.update_columns(photo_meta: { "exif_distance_m" => 872_303 })

    ValidateTrashJob.perform_now(trash.id)

    trash.reload
    assert_equal 0, @vision_calls
    assert_predicate trash, :needs_review?
    assert_equal({ "reason" => "metadata_mismatch" }, trash.ai_payload)
  end

  test "does not re-validate a report that already has an outcome" do
    trash = sanitized_trash
    trash.update_columns(ai_status: "needs_review")

    ValidateTrashJob.perform_now(trash.id)

    assert_equal 0, @vision_calls
    assert_predicate trash.reload, :needs_review?
  end

  test "if the AI keeps failing the report is held for review, not left pending" do
    attempts = 0
    TrashVision.provider = ->(_photo) { attempts += 1; raise "vision is down" }
    trash = sanitized_trash

    perform_enqueued_jobs { ValidateTrashJob.perform_later(trash.id) }

    trash.reload
    assert_equal 5, attempts
    assert_predicate trash, :needs_review?
    assert_match(/validation_failed: RuntimeError/, trash.ai_payload["hold_reason"])
  end

  test "a garbled answer from the provider holds the report for review and never publishes it" do
    TrashVision.provider = ->(_photo) { { is_trash: true, severity: 150, confidence: 0.99 } }
    trash = sanitized_trash

    perform_enqueued_jobs { ValidateTrashJob.perform_later(trash.id) }

    trash.reload
    assert_predicate trash, :needs_review?
    assert_nil trash.severity
    assert_match(/validation_failed: TrashVision::InvalidResponse/, trash.ai_payload["hold_reason"])
  end

  test "a provider that answers with a plain hash works" do
    TrashVision.provider = ->(_photo) { { "is_trash" => true, "severity" => 35, "types" => ["glass"], "confidence" => 0.8 } }
    trash = sanitized_trash

    ValidateTrashJob.perform_now(trash.id)

    trash.reload
    assert_predicate trash, :validated?
    assert_equal 35, trash.severity
    assert_equal %w[glass], trash.trash_types
  end

  test "ignores a report that no longer exists" do
    assert_nothing_raised { ValidateTrashJob.perform_now(0) }
  end

  # --- "Já foi limpo": a photo that says a reported place is clean now ---

  def cleanup_trash(**attrs)
    sanitized_trash(kind: "cleanup", **attrs)
  end

  test "a cleanup the AI confirms goes to the map with severity 0" do
    create_published_trash(severity: 80) # something to clean, in the same cell
    @vision_answer = vision_result(is_trash: false, severity: nil, types: [], confidence: 0.93)
    trash = cleanup_trash

    ValidateTrashJob.perform_now(trash.id)

    trash.reload
    assert_predicate trash, :validated?
    assert_equal 0, trash.severity
    assert_empty trash.trash_types
    assert_not_nil trash.published_at
  end

  test "a few leftover items still count as cleaned" do
    create_published_trash(severity: 80)
    @vision_answer = vision_result(severity: ValidateTrashJob::CLEANED_MAX_SEVERITY, confidence: 0.9)
    trash = cleanup_trash

    ValidateTrashJob.perform_now(trash.id)

    assert_predicate trash.reload, :validated?
    assert_equal ValidateTrashJob::CLEANED_MAX_SEVERITY, trash.severity
  end

  test "a cleanup photo that still shows trash is rejected as still_dirty" do
    create_published_trash(severity: 80)
    @vision_answer = vision_result(severity: 60, confidence: 0.95)
    trash = cleanup_trash

    ValidateTrashJob.perform_now(trash.id)

    trash.reload
    assert_predicate trash, :rejected?
    assert_equal "still_dirty", trash.ai_payload["reason"]
    assert_nil trash.published_at
  end

  test "a cleanup where nothing was reported is rejected without paying for the AI" do
    trash = cleanup_trash

    ValidateTrashJob.perform_now(trash.id)

    assert_equal 0, @vision_calls
    assert_predicate trash.reload, :rejected?
    assert_equal "nothing_to_clean", trash.ai_payload["reason"]
  end

  test "a cleanup needs a surer AI than a report: 0.7 goes to review" do
    create_published_trash(severity: 80)
    @vision_answer = vision_result(is_trash: false, severity: nil, types: [], confidence: 0.7)
    trash = cleanup_trash

    ValidateTrashJob.perform_now(trash.id)

    assert_predicate trash.reload, :needs_review?
    assert_not Trash.for_heatmap.exists?(trash.id)
  end

  test "an accepted cleanup clears the cell and the heat map keeps it as a green pin" do
    dirty = create_published_trash(severity: 80, taken_at: 2.days.ago)
    RefreshHeatCellJob.perform_now(dirty.h3_index)
    @vision_answer = vision_result(is_trash: false, severity: nil, types: [], confidence: 0.95)
    trash = cleanup_trash

    perform_enqueued_jobs { ValidateTrashJob.perform_now(trash.id) }

    cell = HeatCell.find_by!(h3_index: dirty.h3_index)
    assert_in_delta 0, cell.score, 0.01
    assert_not_nil cell.cleaned_at
    assert_equal true, cell.to_feature[:properties][:cleaned]
  end
end
