# Warn loudly at boot when demo mode is on. App classes (DemoMode, PhotoSanitizer) are not loadable
# while initializers run, so everything that touches them happens in after_initialize.
Rails.application.config.after_initialize do
  if DemoMode.enabled?
    exif = PhotoSanitizer.keep_metadata? ? "EXIF (GPS, camera) is kept in stored photos" : "EXIF is stripped from stored photos"
    Rails.logger.warn(
      "[DEMO MODE] Fake AI results and NO face/plate detection: uploaded photos are not blurred. " \
      "#{exif}. Do not use with real users."
    )
  end
end
