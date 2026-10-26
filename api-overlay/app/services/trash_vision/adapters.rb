# Ready-made providers for TrashVision, chosen with environment variables so nothing in the code
# changes when you switch vendor:
#
#   TRASH_VISION_PROVIDER=anthropic   ANTHROPIC_API_KEY=...   [TRASH_VISION_MODEL=claude-sonnet-5-5]
#   TRASH_VISION_PROVIDER=openai      OPENAI_API_KEY=...      TRASH_VISION_MODEL=<a vision model>
#                                     [OPENAI_BASE_URL=...]   (any OpenAI-compatible endpoint)
#
# Each adapter is a plain object with #call(image). To add another vendor, write a class like
# these and map its name in .from_env, or skip this and set TrashVision.provider yourself.
class TrashVision
  module Adapters
    # A request that did not come back with a 2xx. The job retries it, then sends the report to a human.
    class RequestFailed < StandardError; end

    PROVIDERS = {
      "anthropic" => "Anthropic",
      "openai" => "OpenAI"
    }.freeze

    # nil when TRASH_VISION_PROVIDER is not set.
    def self.from_env(env = ENV)
      name = env["TRASH_VISION_PROVIDER"].to_s.strip.downcase
      return nil if name.empty?

      klass = PROVIDERS[name] or raise NotConfigured,
        "TRASH_VISION_PROVIDER=#{name.inspect} is not known. Use one of: #{PROVIDERS.keys.join(', ')}"
      const_get(klass).new(env: env)
    end
  end
end
