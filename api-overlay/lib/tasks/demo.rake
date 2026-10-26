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

namespace :vision do
  desc "Run photos through several AI providers and print the answers side by side. DIR=photos PROVIDERS=anthropic,gemini"
  task compare: :environment do
    dir = ENV.fetch("DIR") { abort "Set DIR to a folder with .jpg, .png or .webp photos" }
    paths = Dir.glob(File.join(dir, "*")).select { |f| TrashVision::Comparison::CONTENT_TYPES.key?(File.extname(f).downcase) }.sort
    abort "No photos found in #{dir}" if paths.empty?

    # Each name gets its own settings, so several providers can run in one go.
    #   anthropic: ANTHROPIC_API_KEY, TRASH_VISION_MODEL (optional)
    #   gemini:    GEMINI_API_KEY, GEMINI_MODEL (required), through Google's OpenAI-compatible endpoint
    #   openai:    OPENAI_API_KEY, OPENAI_MODEL (required), OPENAI_BASE_URL (optional)
    builders = {
      "anthropic" => -> { TrashVision::Adapters::Anthropic.new(env: ENV.to_h.merge("TRASH_VISION_MODEL" => ENV["ANTHROPIC_MODEL"] || ENV["TRASH_VISION_MODEL"])) },
      "gemini" => lambda {
        TrashVision::Adapters::OpenAI.new(env: {
          "OPENAI_API_KEY" => ENV["GEMINI_API_KEY"], "TRASH_VISION_MODEL" => ENV.fetch("GEMINI_MODEL", "gemini-3.8-flash"),
          "OPENAI_BASE_URL" => ENV.fetch("GEMINI_BASE_URL", "https://generativelanguage.googleapis.com/v1beta/openai")
        })
      },
      "openai" => lambda {
        TrashVision::Adapters::OpenAI.new(env: ENV.to_h.merge("TRASH_VISION_MODEL" => ENV["OPENAI_MODEL"]))
      }
    }
    names = ENV.fetch("PROVIDERS", "anthropic,gemini").split(",").map(&:strip)
    unknown = names - builders.keys
    abort "Unknown provider(s): #{unknown.join(', ')}. Use: #{builders.keys.join(', ')}" if unknown.any?

    providers = names.to_h { |name| [name, builders.fetch(name).call] }
    puts "#{paths.size} photo(s), providers: #{names.join(', ')}\n\n"
    puts TrashVision::Comparison.table(TrashVision::Comparison.new(providers: providers).run(paths))
  end
end
