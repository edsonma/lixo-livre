# A rectangle of a photo that must be redacted (a face, a license plate, ...).
#
# Coordinates are normalized to the image: 0.0 to 1.0, origin at the top-left, so they do not
# depend on the resolution the detector looked at.
class PrivacyRegion
  KINDS = %w[face license_plate other].freeze
  PADDING = 0.2 # grow each box by 20% per side: detectors return tight boxes, and edges leak identity

  attr_reader :kind, :x, :y, :width, :height

  # Builds a region from a provider hash ({kind:, x:, y:, width:, height:}, symbol or string keys).
  # Returns nil when the box has no area inside the image (nothing to redact).
  # Raises ArgumentError when the hash is malformed: we cannot guess where to blur.
  def self.from_hash(hash)
    raise ArgumentError, "region must be a Hash, got #{hash.class}" unless hash.respond_to?(:to_h)

    data = hash.to_h.transform_keys(&:to_sym)
    x, y, width, height = %i[x y width height].map do |key|
      Float(data.fetch(key) { raise ArgumentError, "region is missing #{key}" })
    end
    raise ArgumentError, "region has a non-finite number" unless [x, y, width, height].all?(&:finite?)

    left = [x, 0.0].max
    top = [y, 0.0].max
    right = [x + width, 1.0].min
    bottom = [y + height, 1.0].min
    return nil unless right > left && bottom > top

    new(kind: data[:kind], x: left, y: top, width: right - left, height: bottom - top)
  end

  def initialize(kind:, x:, y:, width:, height:)
    kind = kind.to_s
    @kind = KINDS.include?(kind) ? kind : "other" # unknown kinds are still redacted
    @x = x
    @y = y
    @width = width
    @height = height
  end

  # Pixel box [left, top, width, height] for an image of the given size: padded, clamped to the
  # image, at least 1x1.
  def to_pixels(image_width, image_height, padding: PADDING)
    pad_x = width * padding
    pad_y = height * padding

    left = ((x - pad_x) * image_width).floor.clamp(0, image_width - 1)
    top = ((y - pad_y) * image_height).floor.clamp(0, image_height - 1)
    right = ((x + width + pad_x) * image_width).ceil.clamp(left + 1, image_width)
    bottom = ((y + height + pad_y) * image_height).ceil.clamp(top + 1, image_height)

    [left, top, right - left, bottom - top]
  end

  def ==(other)
    other.is_a?(PrivacyRegion) && [kind, x, y, width, height] == [other.kind, other.x, other.y, other.width, other.height]
  end
end
