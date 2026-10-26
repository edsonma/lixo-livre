class TrashVision
  module Adapters
    # Any OpenAI-compatible chat completions endpoint with image input. There is no default model:
    # vendors retire them, so you choose one with TRASH_VISION_MODEL.
    class OpenAiCompatible < Base
      def call(image)
        json_mode = env["TRASH_VISION_JSON_MODE"].to_s.strip.downcase != "off" && @json_mode != false
        reply = begin
          request(image, json_mode: json_mode)
        rescue RequestFailed => e
          # Some compatible servers reject response_format. Ask once more without it, and remember.
          raise unless json_mode && e.message.include?("HTTP 400")

          @json_mode = false
          request(image, json_mode: false)
        end
        content = reply.dig("choices", 0, "message", "content")
        answer = begin
          JSON.parse(strip_code_fence(content.to_s))
        rescue JSON::ParserError
          raise InvalidResponse, "the model did not return JSON"
        end
        raise InvalidResponse, "the model returned #{answer.class}, expected a JSON object" unless answer.is_a?(Hash)

        answer.merge(raw: { provider: "openai", model: reply["model"], usage: reply["usage"], answer: answer })
      end

      private

      def request(image, json_mode:)
        post_json(
          "#{optional('OPENAI_BASE_URL', 'https://api.openai.com/v1')}/chat/completions",
          { "authorization" => "Bearer #{required('OPENAI_API_KEY')}" },
          body(image, json_mode: json_mode)
        )
      end

      # Models without JSON mode like to wrap the answer in ```json ... ```.
      def strip_code_fence(text)
        text.strip.sub(/\A```(?:json)?\s*/i, "").sub(/\s*```\z/, "")
      end

      def body(image, json_mode:)
        {
          model: required("TRASH_VISION_MODEL"),
          **(json_mode ? { response_format: { type: "json_object" } } : {}),
          max_tokens: 400,
          messages: [{
            role: "user",
            content: [
              { type: "text", text: "#{prompt}\nReply with a JSON object with the keys is_trash, severity, types, confidence." },
              { type: "image_url", image_url: { url: image.data_uri } }
            ]
          }]
        }
      end
    end
  end
end
