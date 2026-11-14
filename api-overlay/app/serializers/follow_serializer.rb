# A followed place, with its score and position from the heat map. `cells` is HeatCell.by_h3 for the
# follows being sent, so a list of follows does one query for all its cells instead of one per row.
class FollowSerializer < ApplicationSerializer
  def initialize(record, cells:)
    super(record)
    @cell = cells[record.h3_index]
  end

  def as_json(*)
    { h3: record.h3_index, score: @cell&.score&.round(1), lat: @cell&.lonlat&.y, lng: @cell&.lonlat&.x, since: record.created_at }
  end
end
