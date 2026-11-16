# Pick the Active Storage service from the environment, so a host can switch from the local disk
# (a Railway volume, for the demo) to S3-compatible storage without a code change:
#   ACTIVE_STORAGE_SERVICE=local   (default)   files in storage/, mount a volume there
#   ACTIVE_STORAGE_SERVICE=s3                  see the s3 entry in config/storage.yml
if ENV["ACTIVE_STORAGE_SERVICE"].present?
  Rails.application.config.active_storage.service = ENV["ACTIVE_STORAGE_SERVICE"].to_sym
end

# How photo URLs reach the browser.
#   proxy (default)  the app streams the file, so every photo URL is on the app's own origin. The web app
#                    needs that: the "before / after" share card draws photos onto a canvas, and a browser
#                    refuses to export a canvas that holds an image from another origin (a bucket) unless
#                    the bucket sends CORS headers. It also keeps the bucket's address out of the page.
#   redirect         Active Storage's own default: a 302 to a short-lived link on the bucket. Less load on the
#                    app, but the bucket then needs CORS for your domain, and the share card needs
#                    `crossOrigin = "anonymous"` on its images.
# ACTIVE_STORAGE_DELIVERY=redirect switches back.
Rails.application.config.active_storage.resolve_model_to_route =
  ENV["ACTIVE_STORAGE_DELIVERY"].to_s.strip.downcase == "redirect" ? :rails_storage_redirect : :rails_storage_proxy
