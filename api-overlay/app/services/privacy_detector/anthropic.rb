require "vips"

class PrivacyDetector
  # Finds faces and license plates with Claude (vision). Used when PRIVACY_DETECTOR=anthropic, or
  # automatically when TRASH_VISION_PROVIDER=anthropic (see PrivacyDetector.from_env).
  #
  #   ANTHROPIC_API_KEY=...                   the same key the trash analysis uses
  #   PRIVACY_DETECTOR_MODEL=claude-sonnet-5-5   (a smaller model is cheaper but places boxes less precisely)
  #
  # It receives the metadata-free JPEG, so no GPS or device data leaves the server. A language model
  # estimates boxes, it does not measure them: the boxes are grown (PrivacyRegion::PADDING) and the
  # prompt asks for generous ones. If the API fails this raises, the job retries, and then the photo
  # stays private and goes to human review.
  class Anthropic < TrashVision::Adapters::Base
    DEFAULT_MODEL = "claude-sonnet-5-5".freeze
    API_VERSION = "2023-06-01".freeze
    TOOL = "report_privacy_regions".freeze
    SEND_MAX_PX = 1568 # larger images are shrunk by the API anyway; the boxes are normalized, so size does not matter

    PROMPT = <<~TEXT.freeze
      You protect people's privacy in photos of street litter that will be shown publicly.
      Find every region that must be blurred:
        - "face": any human face that could be recognized, including children, people far away, partly
          visible faces, faces in mirrors or windows, and faces on posters or screens. Box the whole head.
        - "license_plate": any vehicle license plate, readable or not, on cars, motorcycles, trucks, bikes.
      Give each box as fractions of the image: x and y are the top-left corner, width and height the size,
      all between 0 and 1, origin at the top-left. Make boxes slightly LARGER than the object, never tighter.
      Report every instance. If there are none, return an empty list. Answer by calling the #{TOOL} tool.
    TEXT

    SCHEMA = {
      type: "object",
      additionalProperties: false,
      required: %w[regions],
      properties: {
        regions: {
          type: "array",
          items: {
            type: "object",
            additionalProperties: false,
            required: %w[kind x y width height],
            properties: {
              kind: { type: "string", enum: %w[face license_plate] },
              x: { type: "number", minimum: 0, maximum: 1 },
              y: { type: "number", minimum: 0, maximum: 1 },
              width: { type: "number", minimum: 0, maximum: 1 },
              height: { type: "number", minimum: 0, maximum: 1 }
            }
          }
        }
      }
    }.freeze

    # bytes: a JPEG. Returns an array of region hashes (PrivacyDetector turns them into PrivacyRegion).
    def call(bytes)
      reply = post_json(
        "#{optional('ANTHROPIC_BASE_URL', 'https://api.anthropic.com')}/v1/messages",
        { "x-api-key" => required("ANTHROPIC_API_KEY"), "anthropic-version" => API_VERSION },
        body(bytes)
      )
      answer = reply["content"].to_a.find { |block| block["type"] == "tool_use" && block["name"] == TOOL }
      regions = answer && answer["input"].is_a?(Hash) ? answer["input"]["regions"] : nil
      unless regions.is_a?(Array)
        raise PrivacyDetector::InvalidResponse, "Claude did not call #{TOOL} (stop_reason #{reply['stop_reason'].inspect})"
      end

      regions
    end

    private

    def body(bytes)
      {
        model: optional("PRIVACY_DETECTOR_MODEL", DEFAULT_MODEL),
        max_tokens: 1000,
        tools: [{ name: TOOL, description: "Report the regions to blur.", input_schema: SCHEMA }],
        tool_choice: { type: "auto" }, # a forced tool call is refused by some models; the prompt asks for the tool
        messages: [{
          role: "user",
          content: [
            { type: "image", source: { type: "base64", media_type: "image/jpeg", data: Base64.strict_encode64(shrink(bytes)) } },
            { type: "text", text: PROMPT }
          ]
        }]
      }
    end

    def shrink(bytes)
      Vips::Image.thumbnail_buffer(bytes, SEND_MAX_PX, size: :down).write_to_buffer(".jpg", Q: 85, strip: true)
    rescue Vips::Error
      bytes
    end
  end
end
