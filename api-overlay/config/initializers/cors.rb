# Only the web app needs CORS. The React Native app is not a browser and ignores it.
Rails.application.config.middleware.insert_before 0, Rack::Cors do
  allow do
    origins ENV.fetch("WEB_ORIGINS", "http://localhost:5173").split(",")
    resource "/api/*",
             headers: :any,
             methods: %i[get post options head]
  end
end
