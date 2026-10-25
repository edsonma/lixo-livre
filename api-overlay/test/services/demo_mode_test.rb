require "test_helper"

class DemoModeTest < ActiveSupport::TestCase
  test "is off unless DEMO_MODE says otherwise" do
    with_env("DEMO_MODE" => nil) { assert_not DemoMode.enabled? }
    with_env("DEMO_MODE" => "false") { assert_not DemoMode.enabled? }
    with_env("DEMO_MODE" => "banana") { assert_not DemoMode.enabled? }
  end

  test "accepts the usual spellings of true" do
    %w[true TRUE 1 yes on].each do |value|
      with_env("DEMO_MODE" => value) { assert DemoMode.enabled?, "#{value} should enable demo mode" }
    end
  end

  test "fakes are allowed in development and test, and in production only in demo mode" do
    with_env("DEMO_MODE" => nil) do
      assert DemoMode.fakes_allowed?(ActiveSupport::EnvironmentInquirer.new("development"))
      assert DemoMode.fakes_allowed?(ActiveSupport::EnvironmentInquirer.new("test"))
      assert_not DemoMode.fakes_allowed?(ActiveSupport::EnvironmentInquirer.new("production"))
    end
    with_env("DEMO_MODE" => "true") do
      assert DemoMode.fakes_allowed?(ActiveSupport::EnvironmentInquirer.new("production"))
    end
  end

  test "center defaults to Brasilia" do
    with_env("DEMO_CENTER" => nil) { assert_equal DemoMode::DEFAULT_CENTER, DemoMode.center }
  end

  test "center reads DEMO_CENTER as lat,lng" do
    with_env("DEMO_CENTER" => "-23.55, -46.63") { assert_equal [-23.55, -46.63], DemoMode.center }
  end

  test "an invalid DEMO_CENTER falls back to the default" do
    ["nonsense", "1", "95,10", "10,200", "a,b", ""].each do |value|
      with_env("DEMO_CENTER" => value) { assert_equal DemoMode::DEFAULT_CENTER, DemoMode.center, value.inspect }
    end
  end

  test "production without demo mode refuses the fake AI instead of silently using it" do
    with_env("DEMO_MODE" => nil) do
      assert_raises(TrashVision::NotConfigured) { TrashVision.default_provider(local: false).call(nil) }
      assert_raises(PrivacyDetector::NotConfigured) { PrivacyDetector.default_provider(local: false).call("bytes") }
    end
  end
end
