require "test_helper"

class PrivacyDetectorTest < ActiveSupport::TestCase
  class DetectorDown < StandardError; end

  FACE = { kind: "face", x: 0.1, y: 0.1, width: 0.2, height: 0.2 }.freeze

  test "turns provider hashes into regions" do
    Photos::PrivacyDetector.provider = ->(_bytes) { [FACE, FACE.merge(kind: "license_plate").transform_keys(&:to_s)] }

    regions = Photos::PrivacyDetector.detect("jpeg bytes")

    assert_equal %w[face license_plate], regions.map(&:kind)
    assert(regions.all? { |r| r.is_a?(Photos::PrivacyRegion) })
  end

  test "hands the bytes it was given to the provider" do
    seen = nil
    Photos::PrivacyDetector.provider = ->(bytes) { seen = bytes; [] }

    Photos::PrivacyDetector.detect("the jpeg")

    assert_equal "the jpeg", seen
  end

  test "accepts ready-made regions and a single hash" do
    region = Photos::PrivacyRegion.from_hash(FACE)

    Photos::PrivacyDetector.provider = ->(_bytes) { [region] }
    assert_equal [region], Photos::PrivacyDetector.detect("x")

    Photos::PrivacyDetector.provider = ->(_bytes) { FACE }
    assert_equal [region], Photos::PrivacyDetector.detect("x")

    Photos::PrivacyDetector.provider = ->(_bytes) { nil }
    assert_equal [], Photos::PrivacyDetector.detect("x")
  end

  test "drops regions that have no area inside the image" do
    Photos::PrivacyDetector.provider = ->(_bytes) { [FACE.merge(x: 1.5), FACE] }

    assert_equal 1, Photos::PrivacyDetector.detect("x").size
  end

  test "raises InvalidResponse when the provider returns something unusable" do
    [
      [{ kind: "face", x: "oops", y: 0, width: 0.1, height: 0.1 }],
      [{ kind: "face", x: 0.1 }],
      ["not a region"],
      [{ kind: "face", x: nil, y: 0, width: 0.1, height: 0.1 }]
    ].each do |bad|
      Photos::PrivacyDetector.provider = ->(_bytes) { bad }

      assert_raises(Photos::PrivacyDetector::InvalidResponse, "should reject #{bad.inspect}") { Photos::PrivacyDetector.detect("x") }
    end
  end

  test "lets provider errors through, so the caller can fail closed" do
    Photos::PrivacyDetector.provider = ->(_bytes) { raise DetectorDown, "provider is down" }

    assert_raises(DetectorDown) { Photos::PrivacyDetector.detect("x") }
  end

  test "the development default detects nothing" do
    assert_equal [], Photos::PrivacyDetector.default_provider(local: true).call("x")
  end

  test "the production default refuses to run until a real detector is configured" do
    assert_raises(Photos::PrivacyDetector::NotConfigured) { Photos::PrivacyDetector.default_provider(local: false).call("x") }
  end

  test "SKIP_PRIVACY_DETECTOR turns detection off, even in production" do
    with_env("SKIP_PRIVACY_DETECTOR" => "true", "PRIVACY_DETECTOR" => "anthropic", "ANTHROPIC_API_KEY" => "k") do
      assert_equal [], Photos::PrivacyDetector.default_provider(local: false).call("x")
    end
  end
end
