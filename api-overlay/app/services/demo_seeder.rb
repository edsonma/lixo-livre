# Fills the database with fake but realistic data so a fresh deployment has something to show:
# demo users and devices, reports clustered into dirty areas (see DemoPlan), each with a synthetic
# photo, already "validated" and "sanitized", and the heat cells computed.
#
#   DemoSeeder.call            # does nothing if there are already reports
#   DemoSeeder.call(count: 50) # fewer reports
#   DemoSeeder.reset!          # removes only what this class created
#
# It bypasses the photo and AI pipeline on purpose (the photos are already safe and the answers
# are made up), so it needs neither libvips nor an AI provider.
class DemoSeeder
  USER_DOMAIN = "demo.lixolivre.test"
  TOKEN_PREFIX = "demo-"
  PHOTO_DIR = Rails.root.join("db/demo_photos")
  USERS = [["Ana Souza", "ana"], ["Carlos Lima", "carlos"], ["Bia Santos", "bia"]].freeze

  def self.call(**options)
    new(**options).call
  end

  # Deletes the demo reports, devices and users, then re-scores the heat cells.
  def self.reset!
    Trash.where("ai_payload ->> 'provider' = 'demo'").find_each(&:destroy)
    Device.where("token LIKE ?", "#{TOKEN_PREFIX}%").find_each(&:destroy)
    User.where("email LIKE ?", "%@#{USER_DOMAIN}").find_each(&:destroy)
    HeatCell.find_each(&:recompute!)
    HeatCell.where(reports_count: 0).delete_all
  end

  def initialize(count: 220, center: DemoMode.center, now: Time.current, seed: 20_261_024, force: false)
    @count = count
    @center = center
    @now = now
    @seed = seed
    @force = force
  end

  def call
    return { skipped: true, reports: Trash.count } if !@force && Trash.exists?

    actors = demo_actors
    plan = DemoPlan.generate(count: @count, center: @center, now: @now, seed: @seed)
    photos = load_photos(plan)

    without_jobs { plan.each { |report| create_report(report, actors, photos) } }
    Trash.for_heatmap.distinct.pluck(:h3_index).each { |h3| RefreshHeatCellJob.perform_now(h3) }

    { skipped: false, reports: Trash.count, users: User.count, devices: Device.count, heat_cells: HeatCell.count }
  end

  private

  # 3 devices that belong to demo users, then anonymous ones (see DemoPlan::ACTORS).
  def demo_actors
    users = USERS.map do |name, slug|
      User.find_or_create_by!(email: "#{slug}@#{USER_DOMAIN}") { |user| user.name = name }
    end
    user_devices = users.map { |user| user.devices.first || Device.create!(token: new_token, user: user) }

    anonymous = Device.where("token LIKE ?", "#{TOKEN_PREFIX}%").where(user_id: nil).order(:id).to_a
    anonymous << Device.create!(token: new_token) while anonymous.size < DemoPlan::ACTORS - DemoPlan::USER_ACTORS

    user_devices + anonymous.first(DemoPlan::ACTORS - DemoPlan::USER_ACTORS)
  end

  def new_token
    "#{TOKEN_PREFIX}#{SecureRandom.hex(10)}"
  end

  # { "severity-3-a.jpg" => bytes }, read once.
  def load_photos(plan)
    plan.map(&:photo).uniq.to_h do |name|
      path = PHOTO_DIR.join(name)
      raise "Missing demo photo #{path} (regenerate with tools/generate_demo_photos.py)" unless path.exist?

      [name, path.binread]
    end
  end

  def create_report(report, actors, photos)
    device = actors.fetch(report.actor)

    Trash.create!(
      device: device,
      user: device.user,
      lonlat: Trash.point(report.lng, report.lat),
      taken_at: report.taken_at,
      created_at: report.taken_at + 5.minutes,
      updated_at: report.taken_at + 5.minutes,
      extra_info: report.extra_info,
      photo: { io: StringIO.new(photos.fetch(report.photo)), filename: report.photo, content_type: "image/jpeg" },
      # The finished state, as if the whole pipeline had run:
      ai_status: "validated",
      severity: report.severity,
      trash_types: report.trash_types,
      ai_confidence: report.confidence,
      ai_payload: { "provider" => "demo" },
      validated_at: report.taken_at + 1.minute,
      published_at: report.taken_at + 2.minutes,
      sanitized_at: report.taken_at + 30.seconds,
      photo_meta: { "exif_present" => false, "redactions" => {} }
    )
  end

  # Creating a report normally queues sanitizing and heat cell jobs; the seeder does that work
  # itself, so the queue is swapped for one that throws jobs away while it runs.
  def without_jobs
    previous = ActiveJob::Base.queue_adapter
    ActiveJob::Base.queue_adapter = :test
    yield
  ensure
    ActiveJob::Base.queue_adapter.enqueued_jobs.clear if ActiveJob::Base.queue_adapter.respond_to?(:enqueued_jobs)
    ActiveJob::Base.queue_adapter = previous
  end
end
