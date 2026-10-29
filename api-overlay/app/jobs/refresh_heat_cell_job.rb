class RefreshHeatCellJob < ApplicationJob
  queue_as :default

  # A failed re-score used to vanish silently and leave a published photo off the map: try again, and say why.
  retry_on StandardError, wait: 5.seconds, attempts: 4 do |job, error|
    Rails.logger.error("[heat] RefreshHeatCellJob gave up for #{job.arguments.first}: #{error.class}: #{error.message}")
  end

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
