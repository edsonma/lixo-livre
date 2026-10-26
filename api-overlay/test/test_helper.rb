ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"
require "rack/test"
require "stringio"

# Helpers shared by every test.
module TrashTestHelpers
  BRASILIA = { lng: -47.8825, lat: -15.7942 }.freeze # the GPS position inside test/fixtures/files/exif_gps.jpg

  # What the fake AI vision provider answers unless a test overrides it.
  def vision_result(**overrides)
    defaults = { is_trash: true, severity: 80, types: %w[plastic], confidence: 0.95, raw: { "provider" => "test" } }
    TrashVision::Result.new(**defaults, **overrides)
  end

  def create_user(**attrs)
    User.create!({ email: "user-#{SecureRandom.hex(4)}@example.com", name: "Test User" }.merge(attrs))
  end

  def create_device(user: nil)
    Device.create!(user: user)
  end

  # Attachable hash for an image in test/fixtures/files.
  def photo_attachable(name = "plain.jpg", content_type: "image/jpeg")
    { io: StringIO.new(file_fixture(name).binread), filename: name, content_type: content_type }
  end

  # A multipart upload for integration tests.
  def uploaded_photo(name = "plain.jpg", content_type = "image/jpeg")
    Rack::Test::UploadedFile.new(file_fixture(name).to_s, content_type)
  end

  # A fresh report as the API would create it: pending, photo not yet sanitized.
  def create_trash(device: nil, lng: BRASILIA[:lng], lat: BRASILIA[:lat], taken_at: 1.hour.ago,
                   fixture: "plain.jpg", photo: nil, **attrs)
    Trash.create!(
      device: device || create_device,
      lonlat: Trash.point(lng, lat),
      taken_at: taken_at,
      photo: photo || photo_attachable(fixture),
      **attrs
    )
  end

  # A report that already went through the whole pipeline and is publicly visible.
  # Writes the final state directly, so no jobs run.
  def create_published_trash(severity: 60, **attrs)
    create_draft_trash(severity: severity, **attrs).tap { |trash| trash.update_columns(published_at: Time.current) }
  end

  # A report the AI has scored and whose author has not published yet: private.
  def create_draft_trash(severity: 60, **attrs)
    trash = create_trash(**attrs)
    trash.update_columns(
      ai_status: "validated", severity: severity, trash_types: %w[plastic],
      sanitized_at: Time.current, validated_at: Time.current
    )
    trash
  end

  # Runs the block with environment variables set (nil removes one), then puts them back.
  def with_env(vars)
    saved = vars.keys.to_h { |key| [key, ENV[key]] }
    vars.each { |key, value| value.nil? ? ENV.delete(key) : ENV[key] = value }
    yield
  ensure
    saved.each { |key, value| value.nil? ? ENV.delete(key) : ENV[key] = value }
  end

  # --- image helpers (need libvips) ---

  def decode(bytes)
    Vips::Image.new_from_buffer(bytes, "")
  end

  # Standard deviation of the pixels inside [left, top, width, height].
  # Noise has a high one; a mosaic-redacted region has a very low one.
  def deviation_in(image, box)
    image.crop(*box).deviate
  end
end

class ActiveSupport::TestCase
  include ActiveJob::TestHelper # jobs are queued, not run, unless a test uses perform_enqueued_jobs
  include TrashTestHelpers

  setup do
    TrashVision.provider = ->(_photo) { vision_result }
    PrivacyDetector.provider = ->(_bytes) { [] }
  end

  teardown do
    TrashVision.reset_provider!
    PrivacyDetector.reset_provider!
  end
end
