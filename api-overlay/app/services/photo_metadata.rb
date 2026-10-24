# Reads the few EXIF fields we care about (capture time and GPS position) from a JPEG.
#
# We read them BEFORE the photo is sanitized, only to sanity-check the report (does the photo
# claim to be from somewhere else, or from weeks ago?). The sanitizer then strips everything.
#
# This is a small, bounds-checked reader on purpose: it never raises, and anything it cannot
# understand just comes back as nil. The capture time has no time zone in EXIF, so it is
# returned as if it were UTC; compare with a tolerance of at least a day.
class PhotoMetadata
  attr_reader :taken_at, :lat, :lng

  def self.read(bytes)
    tiff = exif_segment(bytes.to_s.b)
    return new(exif: false) unless tiff

    Tiff.new(tiff).metadata
  rescue StandardError
    new(exif: true) # there is an EXIF block, but we could not make sense of it
  end

  def initialize(exif: false, taken_at: nil, lat: nil, lng: nil)
    @exif = exif
    @taken_at = taken_at
    @lat = lat
    @lng = lng
  end

  # True when the JPEG carries an EXIF block at all (this is also how the tests check stripping).
  def exif?
    @exif
  end

  def gps?
    !lat.nil? && !lng.nil?
  end

  # Returns the TIFF body of the first APP1 "Exif" segment, or nil.
  def self.exif_segment(bytes)
    return nil unless bytes.byteslice(0, 2) == "\xFF\xD8".b

    pos = 2
    64.times do
      pos += 1 while bytes.getbyte(pos) == 0xFF && bytes.getbyte(pos + 1) == 0xFF # fill bytes
      return nil unless bytes.getbyte(pos) == 0xFF

      marker = bytes.getbyte(pos + 1)
      return nil if marker.nil? || marker == 0xD9 || marker == 0xDA # end of image / start of scan

      length = bytes.byteslice(pos + 2, 2)&.unpack1("n")
      return nil if length.nil? || length < 2

      payload = bytes.byteslice(pos + 4, length - 2)
      return payload.byteslice(6..) if marker == 0xE1 && payload&.byteslice(0, 6) == "Exif\0\0".b

      pos += 2 + length
    end
    nil
  end
  private_class_method :exif_segment

  # Minimal TIFF/EXIF structure reader (either byte order).
  class Tiff
    TYPE_SIZE = { 1 => 1, 2 => 1, 3 => 2, 4 => 4, 5 => 8 }.freeze # byte, ascii, short, long, rational
    MAX_ENTRIES = 512
    MAX_VALUES = 8

    EXIF_IFD = 0x8769
    GPS_IFD = 0x8825
    DATE_TIME_ORIGINAL = 0x9003
    DATE_TIME = 0x0132

    def initialize(data)
      @data = data
      @short = { "II" => "v", "MM" => "n" }.fetch(data.byteslice(0, 2)) { raise ArgumentError, "bad byte order" }
      @long = @short == "v" ? "V" : "N"
      raise ArgumentError, "bad TIFF magic" unless u16(2) == 42
    end

    def metadata
      ifd0 = entries(u32(4))
      exif = ifd0[EXIF_IFD] ? entries(value(ifd0[EXIF_IFD]).first) : {}
      gps = ifd0[GPS_IFD] ? entries(value(ifd0[GPS_IFD]).first) : {}

      taken = exif[DATE_TIME_ORIGINAL] || ifd0[DATE_TIME]
      PhotoMetadata.new(
        exif: true,
        taken_at: taken && parse_time(value(taken)),
        lat: coordinate(gps, 1, 2, "S", 90),
        lng: coordinate(gps, 3, 4, "W", 180)
      )
    end

    private

    def fetch(offset, size)
      slice = @data.byteslice(offset, size)
      raise ArgumentError, "read past end of EXIF data" if offset.negative? || slice.nil? || slice.bytesize < size

      slice
    end

    def u16(offset) = fetch(offset, 2).unpack1(@short)
    def u32(offset) = fetch(offset, 4).unpack1(@long)

    # { tag => [type, count, offset_of_value_field] }
    def entries(offset)
      count = [u16(offset), MAX_ENTRIES].min
      count.times.to_h do |i|
        base = offset + 2 + i * 12
        [u16(base), [u16(base + 2), u32(base + 4), base + 8]]
      end
    end

    def value(entry)
      type, count, field = entry
      unit = TYPE_SIZE.fetch(type) { raise ArgumentError, "unsupported type #{type}" }
      raise ArgumentError, "too many values" if count > (type == 2 ? 64 : MAX_VALUES)

      start = unit * count <= 4 ? field : u32(field)
      case type
      when 1 then count.times.map { |i| fetch(start + i, 1).unpack1("C") }
      when 2 then [fetch(start, count).delete("\0").force_encoding(Encoding::ASCII_8BIT)]
      when 3 then count.times.map { |i| u16(start + 2 * i) }
      when 4 then count.times.map { |i| u32(start + 4 * i) }
      when 5 then count.times.map { |i| rational(start + 8 * i) }
      end
    end

    def rational(offset)
      denominator = u32(offset + 4)
      raise ArgumentError, "zero denominator" if denominator.zero?

      Rational(u32(offset), denominator)
    end

    def coordinate(gps, ref_tag, value_tag, negative_ref, limit)
      return nil unless gps[ref_tag] && gps[value_tag]

      degrees, minutes, seconds = value(gps[value_tag])
      return nil if seconds.nil?

      result = (degrees.to_r + minutes.to_r / 60 + seconds.to_r / 3600).to_f
      result = -result if value(gps[ref_tag]).first.upcase.start_with?(negative_ref)
      result.abs <= limit ? result : nil
    end

    # "2026:10:20 14:30:00" -> Time (as UTC; EXIF has no zone)
    def parse_time(values)
      match = values.first.to_s.match(/\A(\d{4}):(\d{2}):(\d{2}) (\d{2}):(\d{2}):(\d{2})/)
      match && Time.utc(*match.captures.map(&:to_i))
    rescue ArgumentError
      nil
    end
  end
end
