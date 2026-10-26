# How clean a place has been over time: one point per month, from the severity (0-100) of the
# reports taken there. Feeds the "Evolução da limpeza" chart on the place screen.
#
#   PlaceHistory.monthly([[80, time], [40, time], ...])
#   # => [{ month: "2026-09", average: 60, reports: 2 }, ...]  oldest first, at most MONTHS entries
#
# Months without reports are left out (the chart joins the points that exist).
class PlaceHistory
  MONTHS = 6

  def self.monthly(rows, months: MONTHS)
    rows
      .group_by { |_severity, taken_at| taken_at.utc.strftime("%Y-%m") }
      .map do |month, entries|
        severities = entries.map(&:first)
        { month: month, average: (severities.sum.to_f / severities.size).round, reports: severities.size }
      end
      .sort_by { |point| point[:month] }
      .last(months)
  end
end
