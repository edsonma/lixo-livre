class TrashVision
  module Adapters
    # Any OpenAI-compatible chat completions endpoint with image input. There is no default model:
    # vendors retire them, so you choose one with TRASH_VISION_MODEL.
    class OpenAI < Base
      def call(image)
        reply = post_json(
          "#{optional('OPENAI_BASE_URL', 'https://api.openai.com/v1')}/chat/completions",
          { "authorization" => "Bearer #{required('OPENAI_API_KEY')}" },
          body(image)
        )
        content = reply.dig("choices", 0, "message", "content")
        answer = begin
          JSON.parse(content.to_s)
        rescue JSON::ParserError
          raise InvalidResponse, "the model did not return JSON"
        end
        raise InvalidResponse, "the model returned #{answer.class}, expected a JSON object" unless answer.is_a?(Hash)

        answer.merge(raw: { provider: "openai", model: reply["model"], usage: reply["usage"], answer: answer })
      end

      private

      def body(image)
        {
          model: required("TRASH_VISION_MODEL"),
          response_format: { type: "json_object" },
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
