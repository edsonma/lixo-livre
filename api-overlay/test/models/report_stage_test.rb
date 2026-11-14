require "test_helper"

# Pure logic: no database needed, the report is a stand-in with the few fields the stage reads.
class ReportStageTest < ActiveSupport::TestCase
  Report = Struct.new(:ai_status, :sanitized_at, :ai_payload, :published, keyword_init: true) do
    def published? = published
  end

  def stage(**attrs)
    ReportStage.of(Report.new(**attrs))
  end

  test "a new report is first protecting its photo, then analyzing it" do
    assert_equal "protecting_photo", stage(ai_status: "pending", sanitized_at: nil)
    assert_equal "analyzing", stage(ai_status: "pending", sanitized_at: Time.current)
  end

  test "a validated report is scored until its author publishes it" do
    assert_equal "scored", stage(ai_status: "validated", published: false)
    assert_equal "published", stage(ai_status: "validated", published: true)
  end

  test "a report held for a person is in review" do
    assert_equal "in_review", stage(ai_status: "needs_review")
  end

  test "a rejected cleanup keeps its own reason; any other rejection is not_trash" do
    assert_equal "still_dirty", stage(ai_status: "rejected", ai_payload: { "reason" => "still_dirty" })
    assert_equal "nothing_to_clean", stage(ai_status: "rejected", ai_payload: { "reason" => "nothing_to_clean" })
    assert_equal "not_trash", stage(ai_status: "rejected", ai_payload: { "reason" => "selfie" })
    assert_equal "not_trash", stage(ai_status: "rejected", ai_payload: nil)
  end
end
