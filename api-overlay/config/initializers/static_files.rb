# The demo page (public/index.html, app.js, app.css) is served by Rails itself. Without this, a phone can
# keep an old copy for hours after a deploy. "no-cache" means: always ask the server, and reuse the
# copy only if it answers "not modified" (a cheap check, the files are small).
Rails.application.config.public_file_server.headers = { "cache-control" => "no-cache" }
