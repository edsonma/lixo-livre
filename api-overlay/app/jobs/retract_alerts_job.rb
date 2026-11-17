# A published report left the map (withdrawn, deleted or hidden): re-score its place and take back the alerts
# that report caused. Idempotent, and safe to run alongside RefreshHeatCellJob.
class RetractAlertsJob < ApplicationJob
  queue_as :default

  def perform(h3_index, since)
    cell = HeatCell.find_or_initialize_by(h3_index: h3_index, resolution: Trash::H3_RESOLUTION)
    cell.recompute!
    Messaging::FollowAlerts.retract(cell, since: Time.zone.parse(since))
  end
end
