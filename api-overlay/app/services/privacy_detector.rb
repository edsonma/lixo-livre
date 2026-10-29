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

    # PRIVACY_DETECTOR=anthropic (or "none") picks the detector. With TRASH_VISION_PROVIDER=anthropic set
    # it is Claude automatically, also in DEMO_MODE, so a real AI never runs on photos without it.
    # nil when nothing is configured. Tests and development never call an API on their own.
    def from_env(env = ENV)
      name = env["PRIVACY_DETECTOR"].to_s.strip.downcase
      name = "anthropic" if name.empty? && env["TRASH_VISION_PROVIDER"].to_s.strip.downcase == "anthropic" && !Rails.env.test?
      case name
      when "", "none" then nil
      when "anthropic" then Anthropic.new(env: env)
      else raise NotConfigured, "PRIVACY_DETECTOR=#{name.inspect} is not known. Use anthropic or none"
      end
    end

    # Development, test and DEMO_MODE detect nothing (unless a real detector is configured) so the
    # pipeline runs end to end. Anywhere else it refuses to run, so a deployment without a real
    # detector never publishes unblurred photos.
    def default_provider(local: DemoMode.fakes_allowed?)
      detector = from_env
      return detector if detector
      return ->(_bytes) { [] } if local

      lambda do |_bytes|
        raise NotConfigured, "Set PRIVACY_DETECTOR=anthropic (with ANTHROPIC_API_KEY), or PrivacyDetector.provider to your own " \
                             "face and license plate detector (or DEMO_MODE=true to skip detection, which blurs nothing)"
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
