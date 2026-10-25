if DemoMode.enabled?
  Rails.application.config.after_initialize do
    Rails.logger.warn(
      "[DEMO MODE] Fake AI results and NO face/plate detection: uploaded photos are not blurred. " \
      "EXIF data is still stripped. Do not use with real users."
    )
  end
end
