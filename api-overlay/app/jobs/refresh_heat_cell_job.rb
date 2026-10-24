class RefreshHeatCellJob < ApplicationJob
  queue_as :default

  def perform(h3_index)
    cell = HeatCell.find_or_initialize_by(h3_index: h3_index, resolution: Trash::H3_RESOLUTION)
    cell.recompute!
  end
end
