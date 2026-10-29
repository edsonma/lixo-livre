require "test_helper"

class PrivacyDetectorAnthropicTest < ActiveSupport::TestCase
  ENV_OK = { "ANTHROPIC_API_KEY" => "sk-test" }.freeze

  def detector(reply, status: 200, env: ENV_OK, seen: [])
    transport = ->(url, headers, body) { seen << [url, headers, body]; [status, JSON.generate(reply)] }
    PrivacyDetector::Anthropic.new(env: env, transport: transport)
  end

  def tool_reply(regions)
    { "content" => [{ "type" => "tool_use", "name" => "report_privacy_regions", "input" => { "regions" => regions } }], "stop_reason" => "tool_use" }
  end

  test "sends the image and the tool, and returns the regions" do
    seen = []
    face = { "kind" => "face", "x" => 0.4, "y" => 0.1, "width" => 0.1, "height" => 0.15 }
    regions = detector(tool_reply([face]), seen: seen).call(file_fixture("plain.jpg").binread)

    assert_equal [face], regions
    url, headers, body = seen.first
    assert_match %r{/v1/messages\z}, url
    assert_equal "sk-test", headers["x-api-key"]
    assert_equal "image", body[:messages][0][:content][0][:type]
    assert_equal "report_privacy_regions", body[:tools][0][:name]
  end

  test "PrivacyDetector turns the answer into regions" do
    face = { "kind" => "license_plate", "x" => 0.5, "y" => 0.5, "width" => 0.2, "height" => 0.1 }
    PrivacyDetector.provider = detector(tool_reply([face]))
    assert_equal ["license_plate"], PrivacyDetector.detect(file_fixture("plain.jpg").binread).map(&:kind)
  end

  test "an empty list means nothing was found" do
    assert_equal [], detector(tool_reply([])).call(file_fixture("plain.jpg").binread)
  end

  test "raises when Claude does not call the tool, so the photo is held for review" do
    reply = { "content" => [{ "type" => "text", "text" => "I see a face" }], "stop_reason" => "end_turn" }
    assert_raises(PrivacyDetector::InvalidResponse) { detector(reply).call(file_fixture("plain.jpg").binread) }
  end

  test "raises when the API fails" do
    d = detector({ "error" => { "message" => "overloaded" } }, status: 529)
    assert_raises(TrashVision::Adapters::RequestFailed) { d.call(file_fixture("plain.jpg").binread) }
  end

  test "needs the API key" do
    assert_raises(TrashVision::NotConfigured) { detector(tool_reply([]), env: {}).call(file_fixture("plain.jpg").binread) }
  end

  test "from_env picks the detector from PRIVACY_DETECTOR" do
    assert_nil PrivacyDetector.from_env({})
    assert_nil PrivacyDetector.from_env({ "PRIVACY_DETECTOR" => "none" })
    assert_kind_of PrivacyDetector::Anthropic, PrivacyDetector.from_env({ "PRIVACY_DETECTOR" => "anthropic", "ANTHROPIC_API_KEY" => "k" })
    assert_raises(PrivacyDetector::NotConfigured) { PrivacyDetector.from_env({ "PRIVACY_DETECTOR" => "magic" }) }
  end
end
