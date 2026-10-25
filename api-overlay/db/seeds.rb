# Fake demo data. Runs in development, and anywhere SEED_DEMO_DATA=true.
# Does nothing when there are already reports, so it is safe to run on every deploy.
# (To seed on demand in any environment: bin/rails demo:seed)
if Rails.env.development? || ENV["SEED_DEMO_DATA"] == "true"
  puts "Demo data: #{DemoSeeder.call(count: ENV.fetch('DEMO_COUNT', 220).to_i).inspect}"
end
