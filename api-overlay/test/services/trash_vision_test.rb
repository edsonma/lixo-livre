require "test_helper"

class TrashVisionTest < ActiveSupport::TestCase
  def answer(**overrides)
    { is_trash: true, severity: 3, types: %w[plastic], confidence: 0.9 }.merge(overrides)
  end

  def analyze_with(response)
    TrashVision.provider = ->(_image) { response }
    TrashVision.analyze(TrashVision::Image.new(bytes: "x", content_type: "image/jpeg"))
  end

  # --- what the provider receives ---

  test "the provider gets an Image with bytes and content type, not an Active Storage object" do
    trash = create_trash
    seen = nil
    TrashVision.provider = ->(image) { seen = image; answer }

    TrashVision.analyze(trash.photo)

    assert_instance_of TrashVision::Image, seen
    assert_equal "image/jpeg", seen.content_type
    assert_equal trash.photo.download, seen.bytes
  end

  test "an Image can hand itself to an API as base64 or a data URI" do
    image = TrashVision::Image.new(bytes: "abc", content_type: "image/png")

    assert_equal "YWJj", image.base64
    assert_equal "data:image/png;base64,YWJj", image.data_uri
  end

  test "any object with #call works as a provider" do
    adapter = Class.new { def call(_image) = { is_trash: false, confidence: 0.8 } }.new
    TrashVision.provider = adapter

    assert_not TrashVision.analyze(TrashVision::Image.new(bytes: "x", content_type: "image/jpeg")).is_trash
  end

  # --- accepted answer shapes ---

  test "accepts a Hash with symbol keys" do
    result = analyze_with(answer)

    assert_instance_of TrashVision::Result, result
    assert_equal [true, 3, %w[plastic], 0.9], [result.is_trash, result.severity, result.types, result.confidence]
  end

  test "accepts a Hash with string keys, like parsed JSON" do
    result = analyze_with(JSON.parse(answer.to_json))

    assert_equal 3, result.severity
    assert_equal %w[plastic], result.types
  end

  test "accepts a TrashVision::Result" do
    result = analyze_with(vision_result(severity: 5))

    assert_equal 5, result.severity
  end

  test "rounds and parses numeric severity and confidence from loose types" do
    result = analyze_with(answer(severity: "4", confidence: "0.75"))

    assert_equal 4, result.severity
    assert_in_delta 0.75, result.confidence
  end

  test "keeps the raw answer for debugging: the provider's own raw if given, else the whole answer" do
    assert_equal({ "why" => "pile of bags" }, analyze_with(answer(raw: { "why" => "pile of bags" })).raw)
    assert_equal "plastic", analyze_with(answer)[:raw]["types"].first
  end

  # --- cleaning ---

  test "drops unknown types, normalizes case and removes duplicates" do
    result = analyze_with(answer(types: ["Plastic", "plastic", "unicorn", " GLASS "]))

    assert_equal %w[plastic glass], result.types
  end

  test "accepts a single type given as a string" do
    assert_equal %w[glass], analyze_with(answer(types: "glass")).types
  end

  test "not trash needs no severity or types, and ignores any it sends" do
    result = analyze_with(is_trash: false, confidence: 0.97, severity: 4, types: %w[plastic])

    assert_not result.is_trash
    assert_nil result.severity
    assert_empty result.types
  end

  # --- rejected answers ---

  test "rejects answers that are not usable" do
    [
      nil, "trash", 42, [],
      answer(is_trash: nil), answer(is_trash: "yes"), answer.except(:is_trash),
      answer(severity: 0), answer(severity: 6), answer(severity: nil), answer(severity: "bad"),
      answer(confidence: nil), answer(confidence: 1.5), answer(confidence: -0.1), answer(confidence: 90), answer(confidence: "high")
    ].each do |bad|
      assert_raises(TrashVision::InvalidResponse, bad.inspect) { analyze_with(bad) }
    end
  end

  test "a provider that raises is not swallowed" do
    TrashVision.provider = ->(_image) { raise "vision is down" }

    assert_raises(RuntimeError) { TrashVision.analyze(TrashVision::Image.new(bytes: "x", content_type: "image/jpeg")) }
  end

  # --- contract helpers for adapters ---

  test "the JSON schema lists exactly the types the app accepts" do
    schema = TrashVision.json_schema

    assert_equal Trash::TYPES, schema[:properties][:types][:items][:enum]
    assert_equal %w[is_trash confidence], schema[:required]
  end

  test "the shared prompt exists for adapters to reuse" do
    assert_includes TrashVision::PROMPT, "is_trash"
  end

  # --- defaults ---

  test "the development default passes its own validation and is confident enough to publish" do
    TrashVision.provider = TrashVision.default_provider(local: true)

    result = TrashVision.analyze(TrashVision::Image.new(bytes: "x", content_type: "image/jpeg"))

    assert result.is_trash
    assert_includes 1..5, result.severity
    assert_operator result.confidence, :>=, ValidateTrashJob::CONFIDENCE_THRESHOLD
  end

  test "the production default refuses to run until a real provider is configured" do
    assert_raises(TrashVision::NotConfigured) { TrashVision.default_provider(local: false).call(nil) }
  end
end
