class RefreshHeatCellJob < ApplicationJob
  queue_as :default

  def perform(h3_index)
    cell = HeatCell.find_or_initialize_by(h3_index: h3_index, resolution: Trash::H3_RESOLUTION)
    cell.recompute!
    begin
      FollowAlerts.run(cell)
    rescue StandardError => e # alerts must never stop a place from being scored
      Rails.logger.error("FollowAlerts failed for #{h3_index}: #{e.class}: #{e.message}")
    end
  end
end
