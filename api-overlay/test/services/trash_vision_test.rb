require "test_helper"

class TrashVisionTest < ActiveSupport::TestCase
  test "analyze delegates to the configured provider" do
    seen = nil
    expected = vision_result(severity: 2)
    TrashVision.provider = ->(photo) { seen = photo; expected }

    assert_same expected, TrashVision.analyze(:the_photo)
    assert_equal :the_photo, seen
  end

  test "the development default returns a plausible fake result" do
    result = TrashVision.default_provider(local: true).call(nil)

    assert result.is_trash
    assert_includes 1..5, result.severity
    assert_empty result.types - Trash::TYPES
    assert_operator result.confidence, :>=, ValidateTrashJob::CONFIDENCE_THRESHOLD
  end

  test "the production default refuses to run until a real provider is configured" do
    assert_raises(TrashVision::NotConfigured) { TrashVision.default_provider(local: false).call(nil) }
  end
end
