# Carries the original photo's EXIF (GPS position, capture time, camera make and model, basic shooting
# settings) over into the sanitized JPEG, which is otherwise built from fresh pixels and has no metadata.
#
# It does NOT copy the original block. It reads a short allowlist of fields and writes a brand new
# EXIF block from them, so nothing else can come along:
#   - no embedded preview image (EXIF thumbnail): it was made from the UNBLURRED original, so
#     keeping it would put a face back into a photo we just blurred
#   - no maker note (cameras hide previews and serial numbers in there), no serial numbers, owner
#     name, user comment or image description
#   - Orientation is written as 1, because the pixels were already rotated upright
#   - the pixel size fields are the size of the new image
# XMP, IPTC and ICC are never copied. Text fields must be plain printable ASCII.
#
# Fail safe: anything unexpected (damaged EXIF, too big) returns the photo with NO metadata, never
# an exception.
#
# ExifPreserver.strip removes the EXIF again; it is used before a photo goes to a third party.
class ExifPreserver
  MAX_TIFF_BYTES = 65_535 - 2 - 6 # one JPEG segment: 2 length bytes + "Exif\0\0"
  MAX_ENTRIES = 512

  ORIENTATION = 0x0112
  EXIF_IFD = 0x8769
  GPS_IFD = 0x8825
  PIXEL_X = 0xA002
  PIXEL_Y = 0xA003

  BYTE = 1
  ASCII = 2
  SHORT = 3
  LONG = 4
  RATIONAL = 5
  TYPE_SIZE = { BYTE => 1, ASCII => 1, SHORT => 2, LONG => 4, RATIONAL => 8, 7 => 1, 9 => 4, 10 => 8 }.freeze

  # tag => [type, most values allowed]
  IFD0_FIELDS = { 0x010F => [ASCII, 64], 0x0110 => [ASCII, 64], 0x0131 => [ASCII, 64], 0x0132 => [ASCII, 20] }.freeze
  EXIF_FIELDS = {
    0x829A => [RATIONAL, 1], 0x829D => [RATIONAL, 1], 0x8827 => [SHORT, 1], 0x9003 => [ASCII, 20],
    0x9004 => [ASCII, 20], 0x920A => [RATIONAL, 1], 0xA434 => [ASCII, 64]
  }.freeze
  GPS_FIELDS = {
    0x01 => [ASCII, 2], 0x02 => [RATIONAL, 3], 0x03 => [ASCII, 2], 0x04 => [RATIONAL, 3],
    0x05 => [BYTE, 1], 0x06 => [RATIONAL, 1], 0x1D => [ASCII, 11]
  }.freeze

  Entry = Struct.new(:tag, :type, :count, :field)
  Field = Struct.new(:tag, :type, :values)

  # original: the uploaded file's bytes. into: the sanitized JPEG. Returns a JPEG.
  def self.copy(original, into:, width:, height:)
    tiff = PhotoMetadata.exif_segment(original.to_s.b)
    return into unless tiff

    clean = new(tiff).rebuilt(width: width, height: height)
    return into if clean.bytesize > MAX_TIFF_BYTES

    jpeg = into.b
    return into unless jpeg.byteslice(0, 2) == "\xFF\xD8".b

    payload = "Exif\0\0".b + clean
    segment = "\xFF\xE1".b + [payload.bytesize + 2].pack("n") + payload
    jpeg.byteslice(0, 2) + segment + jpeg.byteslice(2..)
  rescue StandardError
    into
  end

  # The same JPEG without any EXIF (APP1 "Exif") segment. Other bytes are untouched.
  def self.strip(jpeg)
    bytes = jpeg.to_s.b
    return jpeg unless bytes.byteslice(0, 2) == "\xFF\xD8".b

    kept = [bytes.byteslice(0, 2)]
    pos = 2
    while pos + 4 <= bytes.bytesize && bytes.getbyte(pos) == 0xFF
      marker = bytes.getbyte(pos + 1)
      break if marker == 0xDA || marker == 0xD9 # image data follows

      length = bytes.byteslice(pos + 2, 2).unpack1("n")
      break if length < 2

      segment = bytes.byteslice(pos, 2 + length)
      exif = marker == 0xE1 && bytes.byteslice(pos + 4, 6) == "Exif\0\0".b
      kept << segment unless exif
      pos += 2 + length
    end
    (kept << bytes.byteslice(pos..)).join
  rescue StandardError
    jpeg
  end

  def initialize(tiff)
    @data = tiff.b
    @short = { "II" => "v", "MM" => "n" }.fetch(@data.byteslice(0, 2))
    @long = @short == "v" ? "V" : "N"
    raise ArgumentError, "bad TIFF magic" unless u16(2) == 42
  end

  # A new, little-endian TIFF block with only the allowlisted fields. Raises ArgumentError when
  # the structure of the original cannot be trusted at all.
  def rebuilt(width:, height:)
    ifd0 = entries(u32(4))
    exif_entries = ifd0[EXIF_IFD] ? entries(u32(ifd0[EXIF_IFD].field)) : {}
    gps_entries = ifd0[GPS_IFD] ? entries(u32(ifd0[GPS_IFD].field)) : {}

    ifd0_fields = read_fields(ifd0, IFD0_FIELDS) + [Field.new(ORIENTATION, SHORT, [1])]
    exif_fields = read_fields(exif_entries, EXIF_FIELDS) +
                  [Field.new(PIXEL_X, LONG, [width]), Field.new(PIXEL_Y, LONG, [height])]
    gps_fields = read_fields(gps_entries, GPS_FIELDS)

    serialize(ifd0_fields, exif_fields, gps_fields)
  end

  private

  # --- reading the original (bounds-checked) ---

  def u16(offset) = fetch(offset, 2).unpack1(@short)
  def u32(offset) = fetch(offset, 4).unpack1(@long)

  def fetch(offset, size)
    raise ArgumentError, "offset out of range" if offset.negative? || size.negative? || offset + size > @data.bytesize

    @data.byteslice(offset, size)
  end

  def entries(offset)
    count = u16(offset)
    raise ArgumentError, "too many entries" if count > MAX_ENTRIES

    count.times.to_h do |i|
      base = offset + 2 + i * 12
      [u16(base), Entry.new(u16(base), u16(base + 2), u32(base + 4), base + 8)]
    end
  end

  # Fields that are missing, of the wrong type or unreadable are skipped one by one.
  def read_fields(entries, allowed)
    allowed.filter_map do |tag, (type, max)|
      entry = entries[tag]
      next unless entry && entry.type == type && entry.count.between?(1, max)

      values = read_values(entry)
      Field.new(tag, type, values) if values
    rescue ArgumentError, ZeroDivisionError
      nil
    end
  end

  def read_values(entry)
    unit = TYPE_SIZE.fetch(entry.type)
    start = unit * entry.count <= 4 ? entry.field : u32(entry.field)
    case entry.type
    when BYTE then entry.count.times.map { |i| fetch(start + i, 1).unpack1("C") }
    when ASCII then printable_text(fetch(start, entry.count))
    when SHORT then entry.count.times.map { |i| u16(start + 2 * i) }
    when RATIONAL then entry.count.times.map { |i| rational(start + 8 * i) }
    end
  end

  # Text must be printable ASCII (a trailing NUL is fine). Anything else is not a camera name or a
  # date, so it is dropped rather than copied.
  def printable_text(raw)
    text = raw.sub(/\0+\z/n, "")
    text.match?(/\A[\x20-\x7E]*\z/n) ? text : nil
  end

  def rational(offset)
    Rational(u32(offset), u32(offset + 4)) # a zero denominator raises ZeroDivisionError
  end

  # --- writing the new block (always little endian) ---

  def serialize(ifd0, exif, gps)
    tables = [ifd0]
    exif_pointer = gps_pointer = nil
    unless exif.empty?
      exif_pointer = Field.new(EXIF_IFD, LONG, [0])
      ifd0 << exif_pointer
      tables << exif
    end
    unless gps.empty?
      gps_pointer = Field.new(GPS_IFD, LONG, [0])
      ifd0 << gps_pointer
      tables << gps
    end
    tables.each { |fields| fields.sort_by!(&:tag) }

    offsets = []
    cursor = 8
    tables.each do |fields|
      offsets << cursor
      cursor += 2 + 12 * fields.size + 4
    end
    exif_pointer&.values = [offsets[1]]
    gps_pointer&.values = [offsets[exif_pointer ? 2 : 1]]

    out = "II".b + [42, 8].pack("vV")
    data = "".b
    tables.each do |fields|
      out << [fields.size].pack("v")
      fields.each do |field|
        raw, count = encode(field)
        if raw.bytesize <= 4
          inline = raw.ljust(4, "\0".b)
        else
          inline = [cursor + data.bytesize].pack("V")
          data << raw
          data << "\0".b if raw.bytesize.odd?
        end
        out << [field.tag, field.type, count].pack("vvV") << inline
      end
      out << [0].pack("V") # no next IFD: there is never a preview image
    end
    out << data
  end

  def encode(field)
    case field.type
    when BYTE then [field.values.pack("C*"), field.values.size]
    when ASCII then [field.values.b + "\0".b, field.values.bytesize + 1]
    when SHORT then [field.values.pack("v*"), field.values.size]
    when LONG then [field.values.pack("V*"), field.values.size]
    when RATIONAL then [field.values.map { |r| [r.numerator, r.denominator].pack("VV") }.join, field.values.size]
    end
  end
end
