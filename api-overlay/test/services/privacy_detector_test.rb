require "test_helper"

class PrivacyDetectorTest < ActiveSupport::TestCase
  class DetectorDown < StandardError; end

  FACE = { kind: "face", x: 0.1, y: 0.1, width: 0.2, height: 0.2 }.freeze

  test "turns provider hashes into regions" do
    PrivacyDetector.provider = ->(_bytes) { [FACE, FACE.merge(kind: "license_plate").transform_keys(&:to_s)] }

    regions = PrivacyDetector.detect("jpeg bytes")

    assert_equal %w[face license_plate], regions.map(&:kind)
    assert(regions.all? { |r| r.is_a?(PrivacyRegion) })
  end

  test "hands the bytes it was given to the provider" do
    seen = nil
    PrivacyDetector.provider = ->(bytes) { seen = bytes; [] }

    PrivacyDetector.detect("the jpeg")

    assert_equal "the jpeg", seen
  end

  test "accepts ready-made regions and a single hash" do
    region = PrivacyRegion.from_hash(FACE)

    PrivacyDetector.provider = ->(_bytes) { [region] }
    assert_equal [region], PrivacyDetector.detect("x")

    PrivacyDetector.provider = ->(_bytes) { FACE }
    assert_equal [region], PrivacyDetector.detect("x")

    PrivacyDetector.provider = ->(_bytes) { nil }
    assert_equal [], PrivacyDetector.detect("x")
  end

  test "drops regions that have no area inside the image" do
    PrivacyDetector.provider = ->(_bytes) { [FACE.merge(x: 1.5), FACE] }

    assert_equal 1, PrivacyDetector.detect("x").size
  end

  test "raises InvalidResponse when the provider returns something unusable" do
    [
      [{ kind: "face", x: "oops", y: 0, width: 0.1, height: 0.1 }],
      [{ kind: "face", x: 0.1 }],
      ["not a region"],
      [{ kind: "face", x: nil, y: 0, width: 0.1, height: 0.1 }]
    ].each do |bad|
      PrivacyDetector.provider = ->(_bytes) { bad }

      assert_raises(PrivacyDetector::InvalidResponse, "should reject #{bad.inspect}") { PrivacyDetector.detect("x") }
    end
  end

  test "lets provider errors through, so the caller can fail closed" do
    PrivacyDetector.provider = ->(_bytes) { raise DetectorDown, "provider is down" }

    assert_raises(DetectorDown) { PrivacyDetector.detect("x") }
  end

  test "the development default detects nothing" do
    assert_equal [], PrivacyDetector.default_provider(local: true).call("x")
  end

  test "the production default refuses to run until a real detector is configured" do
    assert_raises(PrivacyDetector::NotConfigured) { PrivacyDetector.default_provider(local: false).call("x") }
  end

  test "SKIP_PRIVACY_DETECTOR turns detection off, even in production" do
    with_env("SKIP_PRIVACY_DETECTOR" => "true", "PRIVACY_DETECTOR" => "anthropic", "ANTHROPIC_API_KEY" => "k") do
      assert_equal [], PrivacyDetector.default_provider(local: false).call("x")
    end
  end
end
