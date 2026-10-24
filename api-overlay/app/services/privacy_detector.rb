# Finds the parts of a photo that identify people: faces and license plates.
#
# The detector is a provider you plug in. It is called with the bytes of a JPEG that has already
# been stripped of all metadata (so no GPS or device info ever reaches a third party) and must
# return an array of regions in normalized coordinates (0.0-1.0, origin top-left):
#
#   [{ kind: "face", x: 0.40, y: 0.10, width: 0.08, height: 0.12 },
#    { kind: "license_plate", x: 0.55, y: 0.70, width: 0.10, height: 0.04 }]
#
# Return [] only when the provider looked and found nothing. If it cannot answer, RAISE: the
# photo then stays private and goes to human review instead of being published unblurred.
class PrivacyDetector
  class NotConfigured < StandardError; end
  class InvalidResponse < StandardError; end

  class << self
    attr_writer :provider

    # Returns an array of PrivacyRegion.
    def detect(bytes)
      parse(provider.call(bytes))
    end

    def provider
      @provider ||= default_provider
    end

    def reset_provider!
      @provider = nil
    end

    # Development and test detect nothing so the pipeline runs end to end. Anywhere else it
    # refuses to run, so a deployment without a real detector never publishes unblurred photos.
    def default_provider(local: Rails.env.local?)
      return ->(_bytes) { [] } if local

      lambda do |_bytes|
        raise NotConfigured, "Set PrivacyDetector.provider to a face and license plate detector"
      end
    end

    private

    def parse(raw)
      list = raw.is_a?(Array) ? raw : [raw].compact
      list.filter_map { |item| item.is_a?(PrivacyRegion) ? item : PrivacyRegion.from_hash(item) }
    rescue ArgumentError, TypeError => e
      raise InvalidResponse, "detector returned something unusable: #{e.message}"
    end
  end
end
