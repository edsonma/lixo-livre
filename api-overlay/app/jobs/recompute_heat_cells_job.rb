# Nightly: time decay changes scores even when no new reports arrive.
#
# It also makes a cell for every published report that has none. A cell is normally made by RefreshHeatCellJob
# right after a report is published, but that job lives in the web process's memory: a restart or a deploy
# at the wrong moment loses it, and a published photo would stay off the map for good. This job runs again
# shortly after every start and then every few hours, so it puts those reports back.
class RecomputeHeatCellsJob < ApplicationJob
  queue_as :default

  def perform
    indexes = Trash.for_heatmap.where.not(h3_index: nil).distinct.pluck(:h3_index) | HeatCell.where(resolution: Trash::H3_RESOLUTION).pluck(:h3_index)
    indexes.each do |h3_index|
      HeatCell.find_or_initialize_by(h3_index: h3_index, resolution: Trash::H3_RESOLUTION).recompute!
    rescue StandardError => e # one bad cell must not keep the rest off the map
      Rails.logger.error("[heat] RecomputeHeatCellsJob could not score #{h3_index}: #{e.class}: #{e.message}")
    end
  end
end
