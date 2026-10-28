# How one map cell's score is made from its published reports. Pure Ruby (no database), so the rules
# are easy to read and test.
#
#   HeatScore.call(rows)  ->  Result(score:, count:, cleaned_at:)
#
# Each row is a HeatScore::Row. The rules:
#   * A report's weight is its severity (0-100), halved every 14 days.
#   * How sure the AI was matters: confidence 0.8 or more counts fully, 0.6-0.8 counts 60%.
#   * One person counts once a day in a cell: of their reports that day only the heaviest is used,
#     so nobody can fill a cell by photographing the same pile over and over.
#   * Different people confirming each other raise the score: +15% for each extra person, up to +45%.
#   * A confirmed cleanup ("Já foi limpo") wipes the reports that came before it: the place was cleaned.
#     Only reports taken after the latest cleanup count again.
class HeatScore
  HALF_LIFE_DAYS = 14
  FULL_CONFIDENCE = 0.8
  MIN_CONFIDENCE = 0.6
  REDUCED_WEIGHT = 0.6
  CONFIRMATION_BONUS = 0.15
  MAX_EXTRA_PEOPLE = 3
  DAY = 86_400.0

  Row = Struct.new(:severity, :taken_at, :confidence, :kind, :reporter, keyword_init: true)
  Result = Struct.new(:score, :count, :cleaned_at, keyword_init: true)

  # severity * 0.5^(age_days / half_life); a report from the future counts fully, never more
  def self.decay(taken_at, now: Time.now)
    age_days = [(now - taken_at) / DAY, 0].max
    0.5**(age_days / HALF_LIFE_DAYS)
  end

  # nil (old or demo data, no confidence recorded) counts fully
  def self.confidence_weight(confidence)
    return 1.0 if confidence.nil? || confidence >= FULL_CONFIDENCE

    REDUCED_WEIGHT
  end

  def self.call(rows, now: Time.now)
    new(rows, now).call
  end

  def initialize(rows, now)
    @rows = rows
    @now = now
  end

  def call
    cleaned_at = @rows.select { |r| r.kind == "cleanup" }.map(&:taken_at).max
    dirty = @rows.reject { |r| r.kind == "cleanup" }
    dirty = dirty.select { |r| r.taken_at > cleaned_at } if cleaned_at

    kept = best_of_each_person_per_day(dirty)
    people = kept.map { |row, _| row.reporter }.uniq.size
    bonus = 1 + CONFIRMATION_BONUS * [people - 1, 0].max.clamp(0, MAX_EXTRA_PEOPLE)

    Result.new(score: kept.sum { |_, weight| weight } * bonus, count: @rows.size, cleaned_at: cleaned_at)
  end

  private

  # [[row, weight], ...] with at most one entry per reporter per UTC day
  def best_of_each_person_per_day(rows)
    rows.map { |row| [row, weight(row)] }
        .group_by { |row, _| [row.reporter, row.taken_at.utc.to_date] }
        .map { |_, group| group.max_by { |_, weight| weight } }
  end

  def weight(row)
    row.severity * self.class.decay(row.taken_at, now: @now) * self.class.confidence_weight(row.confidence)
  end
end
