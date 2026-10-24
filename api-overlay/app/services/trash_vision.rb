# Wrapper around the AI vision provider.
#
# The provider is called with the (already sanitized) photo attachment and must return a Result:
#   is_trash   - false when the photo does not show trash
#   severity   - 1..5
#   types      - subset of Trash::TYPES
#   confidence - 0.0..1.0
#   raw        - the provider's raw response, kept for debugging
class TrashVision
  class NotConfigured < StandardError; end

  Result = Struct.new(:is_trash, :severity, :types, :confidence, :raw, keyword_init: true)

  class << self
    attr_writer :provider

    def analyze(photo)
      provider.call(photo)
    end

    def provider
      @provider ||= default_provider
    end

    def reset_provider!
      @provider = nil
    end

    # Development and test get a fake result so the whole pipeline works end to end.
    # Anywhere else it refuses to run until you plug in a real provider.
    def default_provider(local: Rails.env.local?)
      return ->(_photo) { fake_result } if local

      lambda do |_photo|
        raise NotConfigured, "Set TrashVision.provider to your AI vision provider " \
                             "(send the image, ask for is_trash, severity 1-5, types and confidence)"
      end
    end

    private

    def fake_result
      Result.new(
        is_trash: true,
        severity: rand(1..5),
        types: Trash::TYPES.sample(rand(1..2)),
        confidence: 0.9,
        raw: { provider: "fake" }
      )
    end
  end
end
