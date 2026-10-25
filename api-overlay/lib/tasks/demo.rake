namespace :demo do
  desc "Create fake reports, photos and heat cells (no-op if reports exist; FORCE=true adds anyway, DEMO_COUNT=n sets how many)"
  task seed: :environment do
    result = DemoSeeder.call(count: ENV.fetch("DEMO_COUNT", 220).to_i, force: ENV["FORCE"] == "true")
    puts "Demo data: #{result.inspect}"
  end

  desc "Remove everything demo:seed created (leaves real data alone)"
  task reset: :environment do
    DemoSeeder.reset!
    puts "Demo data removed."
  end
end

namespace :heat do
  desc "Recompute every heat cell now (applies time decay)"
  task recompute: :environment do
    RecomputeHeatCellsJob.perform_now
    puts "Heat cells recomputed: #{HeatCell.count}"
  end
end
