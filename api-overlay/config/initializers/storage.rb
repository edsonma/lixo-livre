# Pick the Active Storage service from the environment, so a host can switch from the local disk
# (a Railway volume, for the demo) to S3-compatible storage without a code change:
#   ACTIVE_STORAGE_SERVICE=local   (default)   files in storage/, mount a volume there
#   ACTIVE_STORAGE_SERVICE=s3                  see the s3 entry in config/storage.yml
if ENV["ACTIVE_STORAGE_SERVICE"].present?
  Rails.application.config.active_storage.service = ENV["ACTIVE_STORAGE_SERVICE"].to_sym
end
