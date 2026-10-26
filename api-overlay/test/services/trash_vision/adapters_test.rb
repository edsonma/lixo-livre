require "test_helper"

class TrashVisionAdaptersTest < ActiveSupport::TestCase
  IMAGE = TrashVision::Image.new(bytes: "\xFF\xD8fake".b, content_type: "image/jpeg")
  SECRET = "sk-test-SECRET-KEY".freeze

  # A fake HTTP layer: records what was sent and answers with a canned status and body.
  def transport(status: 200, body: {})
    sent = []
    callable = lambda do |url, headers, payload|
      sent << { url: url, headers: headers, body: payload }
      [status, body.is_a?(String) ? body : JSON.generate(body)]
    end
    [callable, sent]
  end

  def claude_reply(input)
    { "model" => "claude-sonnet-5-5", "stop_reason" => "tool_use", "usage" => { "input_tokens" => 10 },
      "content" => [{ "type" => "text", "text" => "ok" }, { "type" => "tool_use", "name" => "report_trash", "input" => input }] }
  end

  def openai_reply(content)
    { "model" => "some-model", "choices" => [{ "message" => { "content" => content } }] }
  end

  # --- choosing the provider from the environment ---

  test "no TRASH_VISION_PROVIDER means no adapter" do
    assert_nil TrashVision::Adapters.from_env({})
    assert_nil TrashVision::Adapters.from_env("TRASH_VISION_PROVIDER" => "  ")
  end

  test "the provider name is read without regard to case or spaces" do
    adapter = TrashVision::Adapters.from_env("TRASH_VISION_PROVIDER" => " Anthropic ")
    assert_instance_of TrashVision::Adapters::Anthropic, adapter
    assert_instance_of TrashVision::Adapters::OpenAI, TrashVision::Adapters.from_env("TRASH_VISION_PROVIDER" => "openai")
  end

  test "an unknown provider name is refused and the message lists the valid ones" do
    error = assert_raises(TrashVision::NotConfigured) { TrashVision::Adapters.from_env("TRASH_VISION_PROVIDER" => "skynet") }
    assert_includes error.message, "anthropic"
    assert_includes error.message, "openai"
  end

  test "a missing API key is a clear NotConfigured error" do
    http, sent = transport
    error = assert_raises(TrashVision::NotConfigured) { TrashVision::Adapters::Anthropic.new(env: {}, transport: http).call(IMAGE) }
    assert_includes error.message, "ANTHROPIC_API_KEY"
    assert_empty sent, "nothing is sent without a key"
  end

  # --- Anthropic ---

  test "anthropic sends the image, the prompt and the schema, and reads the tool answer" do
    http, sent = transport(body: claude_reply("is_trash" => true, "severity" => 64, "types" => %w[plastic], "confidence" => 0.93))
    adapter = TrashVision::Adapters::Anthropic.new(env: { "ANTHROPIC_API_KEY" => SECRET }, transport: http)

    answer = TrashVision.normalize(adapter.call(IMAGE))

    assert_equal 64, answer.severity
    assert_equal %w[plastic], answer.types
    assert_in_delta 0.93, answer.confidence
    request = sent.first
    assert_equal "https://api.anthropic.com/v1/messages", request[:url]
    assert_equal SECRET, request[:headers]["x-api-key"]
    assert_equal "claude-sonnet-5-5", request[:body][:model]
    assert_equal({ type: "tool", name: "report_trash" }, request[:body][:tool_choice])
    assert_equal TrashVision.json_schema, request[:body][:tools].first[:input_schema]
    parts = request[:body][:messages].first[:content]
    assert_equal IMAGE.base64, parts.first[:source][:data]
    assert_equal "image/jpeg", parts.first[:source][:media_type]
    assert_includes parts.last[:text], "Allowed types"
  end

  test "the model and base URL can be changed with environment variables" do
    http, sent = transport(body: claude_reply("is_trash" => false, "confidence" => 0.8))
    env = { "ANTHROPIC_API_KEY" => SECRET, "TRASH_VISION_MODEL" => "claude-haiku-5-5", "ANTHROPIC_BASE_URL" => "https://proxy.example" }
    TrashVision::Adapters::Anthropic.new(env: env, transport: http).call(IMAGE)

    assert_equal "https://proxy.example/v1/messages", sent.first[:url]
    assert_equal "claude-haiku-5-5", sent.first[:body][:model]
  end

  test "the kept raw answer has the model and usage but never the key or the photo" do
    http, = transport(body: claude_reply("is_trash" => true, "severity" => 40, "types" => [], "confidence" => 0.9))
    result = TrashVision.normalize(TrashVision::Adapters::Anthropic.new(env: { "ANTHROPIC_API_KEY" => SECRET }, transport: http).call(IMAGE))

    dump = JSON.generate(result.raw)
    assert_equal "anthropic", result.raw[:provider]
    assert_not_includes dump, SECRET
    assert_not_includes dump, IMAGE.base64
  end

  test "a reply without the tool call is an InvalidResponse" do
    http, = transport(body: { "content" => [{ "type" => "text", "text" => "I cannot help" }], "stop_reason" => "end_turn" })
    adapter = TrashVision::Adapters::Anthropic.new(env: { "ANTHROPIC_API_KEY" => SECRET }, transport: http)
    assert_raises(TrashVision::InvalidResponse) { adapter.call(IMAGE) }
  end

  test "an answer outside the allowed ranges is caught by normalize, not trusted" do
    http, = transport(body: claude_reply("is_trash" => true, "severity" => 400, "types" => %w[plastic], "confidence" => 0.9))
    adapter = TrashVision::Adapters::Anthropic.new(env: { "ANTHROPIC_API_KEY" => SECRET }, transport: http)
    assert_raises(TrashVision::InvalidResponse) { TrashVision.normalize(adapter.call(IMAGE)) }
  end

  # --- failures: the job retries these, and the key never shows up in a message ---

  test "an HTTP error becomes RequestFailed with the status and the vendor's message" do
    http, = transport(status: 529, body: { "error" => { "message" => "Overloaded" } })
    adapter = TrashVision::Adapters::Anthropic.new(env: { "ANTHROPIC_API_KEY" => SECRET }, transport: http)
    error = assert_raises(TrashVision::Adapters::RequestFailed) { adapter.call(IMAGE) }
    assert_includes error.message, "529"
    assert_includes error.message, "Overloaded"
  end

  test "a 401 says to check the key, without printing it" do
    http, = transport(status: 401, body: { "error" => { "message" => "invalid x-api-key" } })
    adapter = TrashVision::Adapters::Anthropic.new(env: { "ANTHROPIC_API_KEY" => SECRET }, transport: http)
    error = assert_raises(TrashVision::Adapters::RequestFailed) { adapter.call(IMAGE) }
    assert_includes error.message, "check the API key"
    assert_not_includes error.message, SECRET
  end

  test "a non-JSON body (an HTML error page) is RequestFailed, not a crash" do
    http, = transport(status: 502, body: "<html>Bad gateway</html>")
    adapter = TrashVision::Adapters::Anthropic.new(env: { "ANTHROPIC_API_KEY" => SECRET }, transport: http)
    error = assert_raises(TrashVision::Adapters::RequestFailed) { adapter.call(IMAGE) }
    assert_includes error.message, "502"
  end

  test "a 200 with a body that is not a JSON object is RequestFailed" do
    http, = transport(status: 200, body: "[1, 2]")
    adapter = TrashVision::Adapters::Anthropic.new(env: { "ANTHROPIC_API_KEY" => SECRET }, transport: http)
    assert_raises(TrashVision::Adapters::RequestFailed) { adapter.call(IMAGE) }
  end

  # --- OpenAI-compatible ---

  test "openai needs a model name: there is no default" do
    http, sent = transport
    error = assert_raises(TrashVision::NotConfigured) do
      TrashVision::Adapters::OpenAI.new(env: { "OPENAI_API_KEY" => SECRET }, transport: http).call(IMAGE)
    end
    assert_includes error.message, "TRASH_VISION_MODEL"
    assert_empty sent
  end

  test "openai sends the photo as a data URI and parses the JSON content" do
    http, sent = transport(body: openai_reply('{"is_trash": true, "severity": 71, "types": ["plastic", "unicorn"], "confidence": 0.88}'))
    env = { "OPENAI_API_KEY" => SECRET, "TRASH_VISION_MODEL" => "some-model" }

    answer = TrashVision.normalize(TrashVision::Adapters::OpenAI.new(env: env, transport: http).call(IMAGE))

    assert_equal 71, answer.severity
    assert_equal %w[plastic], answer.types, "unknown types are dropped"
    request = sent.first
    assert_equal "https://api.openai.com/v1/chat/completions", request[:url]
    assert_equal "Bearer #{SECRET}", request[:headers]["authorization"]
    assert_equal "some-model", request[:body][:model]
    image_part = request[:body][:messages].first[:content].last
    assert_equal IMAGE.data_uri, image_part[:image_url][:url]
  end

  test "openai base URL points at any compatible server" do
    http, sent = transport(body: openai_reply('{"is_trash": false, "confidence": 0.7}'))
    env = { "OPENAI_API_KEY" => SECRET, "TRASH_VISION_MODEL" => "m", "OPENAI_BASE_URL" => "http://localhost:11434/v1" }
    TrashVision::Adapters::OpenAI.new(env: env, transport: http).call(IMAGE)
    assert_equal "http://localhost:11434/v1/chat/completions", sent.first[:url]
  end

  test "openai content that is not JSON is an InvalidResponse" do
    http, = transport(body: openai_reply("Sure! Here is my analysis..."))
    env = { "OPENAI_API_KEY" => SECRET, "TRASH_VISION_MODEL" => "m" }
    assert_raises(TrashVision::InvalidResponse) { TrashVision::Adapters::OpenAI.new(env: env, transport: http).call(IMAGE) }
  end

  test "openai content that is JSON but not an object is an InvalidResponse" do
    http, = transport(body: openai_reply("[1]"))
    env = { "OPENAI_API_KEY" => SECRET, "TRASH_VISION_MODEL" => "m" }
    assert_raises(TrashVision::InvalidResponse) { TrashVision::Adapters::OpenAI.new(env: env, transport: http).call(IMAGE) }
  end

  test "openai with no choices is an InvalidResponse" do
    http, = transport(body: { "choices" => [] })
    env = { "OPENAI_API_KEY" => SECRET, "TRASH_VISION_MODEL" => "m" }
    assert_raises(TrashVision::InvalidResponse) { TrashVision::Adapters::OpenAI.new(env: env, transport: http).call(IMAGE) }
  end

  # --- wiring into TrashVision.default_provider ---

  test "default_provider uses the adapter from the environment, even when fakes are allowed" do
    with_env("TRASH_VISION_PROVIDER" => "anthropic") do
      assert_instance_of TrashVision::Adapters::Anthropic, TrashVision.default_provider(local: true)
      assert_instance_of TrashVision::Adapters::Anthropic, TrashVision.default_provider(local: false)
    end
  end

  test "without the variable, fakes stay available locally and refused elsewhere" do
    with_env("TRASH_VISION_PROVIDER" => nil) do
      assert_equal "fake", TrashVision.default_provider(local: true).call(IMAGE)[:raw][:provider]
      error = assert_raises(TrashVision::NotConfigured) { TrashVision.default_provider(local: false).call(IMAGE) }
      assert_includes error.message, "TRASH_VISION_PROVIDER"
    end
  end
end
