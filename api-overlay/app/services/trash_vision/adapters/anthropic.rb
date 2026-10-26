class TrashVision
  module Adapters
    # Claude through the Messages API. The answer is forced through a tool whose input schema is
    # TrashVision.json_schema, so the reply is already structured JSON.
    class Anthropic < Base
      DEFAULT_MODEL = "claude-sonnet-5-5".freeze # claude-haiku-5-5 is cheaper if accuracy is enough
      API_VERSION = "2023-06-01".freeze
      TOOL = "report_trash".freeze

      def call(image)
        reply = post_json(
          "#{optional('ANTHROPIC_BASE_URL', 'https://api.anthropic.com')}/v1/messages",
          { "x-api-key" => required("ANTHROPIC_API_KEY"), "anthropic-version" => API_VERSION },
          body(image)
        )
        answer = reply["content"].to_a.find { |block| block["type"] == "tool_use" && block["name"] == TOOL }
        raise InvalidResponse, "Claude did not call #{TOOL} (stop_reason #{reply['stop_reason'].inspect})" unless answer && answer["input"].is_a?(Hash)

        answer["input"].merge(raw: { provider: "anthropic", model: reply["model"], usage: reply["usage"], answer: answer["input"] })
      end

      private

      def body(image)
        {
          model: optional("TRASH_VISION_MODEL", DEFAULT_MODEL),
          max_tokens: 400,
          tools: [{ name: TOOL, description: "Report what the photo shows.", input_schema: TrashVision.json_schema }],
          tool_choice: { type: "tool", name: TOOL },
          messages: [{
            role: "user",
            content: [
              { type: "image", source: { type: "base64", media_type: image.content_type, data: image.base64 } },
              { type: "text", text: prompt }
            ]
          }]
        }
      end
    end
  end
end
