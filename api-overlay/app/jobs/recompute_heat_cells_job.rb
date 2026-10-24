# Nightly: time decay changes scores even when no new reports arrive.
class RecomputeHeatCellsJob < ApplicationJob
  queue_as :default

  def perform
    HeatCell.find_each(&:recompute!)
  end
end
