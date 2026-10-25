# Decides what the fake demo reports look like: where they are, how dirty, when, of what.
# Pure Ruby (no database, no Rails) and deterministic for a given seed, so it is easy to test.
# DemoSeeder turns the plan into real records.
class DemoPlan
  Report = Struct.new(:lat, :lng, :taken_at, :severity, :trash_types, :extra_info, :photo, :actor,
                      :confidence, keyword_init: true)

  # Dirty areas around the center. east/north: offset in meters; spread: standard deviation in
  # meters; severity: average severity (0-100); share: part of the reports that land here.
  HOTSPOTS = [
    { east: 0,     north: 0,     spread: 250, severity: 88, share: 0.28 },
    { east: 1800,  north: -900,  spread: 350, severity: 72, share: 0.22 },
    { east: -2200, north: 1300,  spread: 300, severity: 56, share: 0.20 },
    { east: 900,   north: 2400,  spread: 400, severity: 40, share: 0.18 },
    { east: -1300, north: -2100, spread: 450, severity: 28, share: 0.12 }
  ].freeze

  DIRTY_TYPES = %w[mixed bulky_items construction_debris organic plastic].freeze
  CLEAN_TYPES = %w[plastic paper glass metal textile].freeze

  NOTES = [
    "Lixo acumulado na esquina", "Sacos de lixo fora da lixeira", "Entulho de obra na calçada",
    "Móveis velhos abandonados", "Garrafas e plástico no canteiro", "Cheiro forte e muitos sacos",
    nil, nil, nil
  ].freeze

  PHOTO_VARIANTS = %w[a b c].freeze
  USER_ACTORS = 3 # actors 0..2 are logged-in users, the rest are anonymous devices
  ACTORS = 8
  MAX_AGE_DAYS = 60
  METERS_PER_DEGREE = 111_320.0

  # The demo photos come in 5 looks, from a few items to a big dump: 0-20 -> 1, 21-40 -> 2 ... 81-100 -> 5.
  def self.photo_bucket(severity)
    (severity / 20.0).ceil.clamp(1, 5)
  end

  # lat/lng for the center, now for the clock; the same seed always gives the same plan.
  def self.generate(count:, center:, now:, seed: 20_261_024)
    new(center: center, now: now, seed: seed).generate(count)
  end

  def initialize(center:, now:, seed:)
    @lat, @lng = center
    @now = now
    @random = Random.new(seed)
  end

  def generate(count)
    hotspot_sequence(count).map { |hotspot| report_in(hotspot) }
  end

  private

  # Hotspot for each report, in proportion to the shares (largest remainder keeps the total exact).
  def hotspot_sequence(count)
    exact = HOTSPOTS.map { |hotspot| hotspot[:share] * count }
    counts = exact.map(&:floor)
    by_remainder = HOTSPOTS.each_index.sort_by { |i| -(exact[i] - counts[i]) }
    (count - counts.sum).times { |n| counts[by_remainder[n % by_remainder.size]] += 1 }

    HOTSPOTS.each_with_index.flat_map { |hotspot, i| [hotspot] * counts[i] }.shuffle(random: @random)
  end

  def report_in(hotspot)
    east = hotspot[:east] + gauss * hotspot[:spread]
    north = hotspot[:north] + gauss * hotspot[:spread]
    severity = (hotspot[:severity] + gauss * 14).round.clamp(0, 100)
    taken_at = @now - age_seconds

    Report.new(
      lat: @lat + north / METERS_PER_DEGREE,
      lng: @lng + east / (METERS_PER_DEGREE * Math.cos(@lat * Math::PI / 180)),
      taken_at: taken_at,
      severity: severity,
      trash_types: (severity >= 80 ? DIRTY_TYPES : CLEAN_TYPES).sample(1 + @random.rand(2), random: @random),
      extra_info: NOTES.sample(random: @random),
      photo: "severity-#{self.class.photo_bucket(severity)}-#{PHOTO_VARIANTS.sample(random: @random)}.jpg",
      actor: @random.rand < 0.55 ? @random.rand(USER_ACTORS) : USER_ACTORS + @random.rand(ACTORS - USER_ACTORS),
      confidence: (0.85 + @random.rand * 0.14).round(2)
    )
  end

  # Standard normal (Box-Muller).
  def gauss
    Math.sqrt(-2 * Math.log(1 - @random.rand)) * Math.cos(2 * Math::PI * @random.rand)
  end

  # Mostly recent, with a long tail (average about 10 days, never over MAX_AGE_DAYS).
  def age_seconds
    seconds = (-10 * Math.log(1 - @random.rand) * 86_400).to_i + @random.rand(0...3_600)
    [seconds, MAX_AGE_DAYS * 86_400].min
  end
end
