require "test_helper"

class TrashTest < ActiveSupport::TestCase
  def build_trash(**attrs)
    Trash.new({
      device: create_device,
      lonlat: Trash.point(-47.8825, -15.7942),
      taken_at: 1.hour.ago,
      photo: photo_attachable
    }.merge(attrs))
  end

  # --- validations ---

  test "is valid with a photo, a position and a time" do
    assert build_trash.valid?
  end

  test "requires photo, position and time" do
    assert_not Trash.new(device: create_device, lonlat: Trash.point(1, 1), taken_at: Time.current).valid?
    assert_not build_trash(lonlat: nil).valid?
    assert_not build_trash(taken_at: nil).valid?
  end

  test "requires a device but not a user" do
    assert_not build_trash(device: nil).valid?
    assert build_trash(user: nil).valid?
  end

  test "severity must be 0 to 100 when present" do
    [-1, 101, 500].each { |bad| assert_not build_trash(severity: bad).valid?, "#{bad} should be invalid" }
    [0, 1, 50, 100, nil].each { |ok| assert build_trash(severity: ok).valid?, "#{ok.inspect} should be valid" }
  end

  test "trash types must be known" do
    trash = build_trash(trash_types: %w[plastic lava])

    assert_not trash.valid?
    assert_match(/lava/, trash.errors[:trash_types].first)
    assert build_trash(trash_types: %w[plastic glass]).valid?
  end

  test "photo must be an image" do
    trash = build_trash(photo: photo_attachable("not_an_image.pdf", content_type: "application/pdf"))

    assert_not trash.valid?
    assert trash.errors[:photo].any? { |m| m.include?("image") }
  end

  test "photo must not be huge" do
    huge = { io: StringIO.new("\0" * (Trash::MAX_PHOTO_BYTES + 1)), filename: "huge.jpg", content_type: "image/jpeg" }
    trash = build_trash(photo: huge)

    assert_not trash.valid?
    assert trash.errors[:photo].any? { |m| m.include?("too large") }
  end

  # --- defaults and callbacks ---

  test "starts pending and not sanitized, with an empty meta hash" do
    trash = create_trash

    assert_predicate trash, :pending?
    assert_nil trash.sanitized_at
    assert_equal({}, trash.reload.photo_meta)
  end

  test "sets the H3 cell from the position" do
    trash = build_trash
    trash.valid?

    assert_match(/\A[0-9a-f]{15}\z/, trash.h3_index)
    assert_equal H3.to_string(H3.from_geo_coordinates([-15.7942, -47.8825], Trash::H3_RESOLUTION)), trash.h3_index
    assert_not_equal trash.h3_index, create_trash(lat: -15.7492).h3_index # 5 km north
  end

  test "creating a report queues sanitizing, and only sanitizing" do
    assert_enqueued_with(job: SanitizePhotoJob) { create_trash }
    assert_no_enqueued_jobs(only: ValidateTrashJob) { create_trash }
  end

  test "the heat cell is refreshed when a report is validated or hidden, not before" do
    trash = create_trash
    cell = trash.h3_index

    assert_no_enqueued_jobs(only: RefreshHeatCellJob) { trash.update!(extra_info: "no status change") }
    assert_enqueued_with(job: RefreshHeatCellJob, args: [cell]) { trash.update!(ai_status: :validated, severity: 3) }
    assert_enqueued_with(job: RefreshHeatCellJob, args: [cell]) { trash.hide! }
  end

  test "hide! sets hidden_at" do
    trash = create_trash
    trash.hide!

    assert_not_nil trash.reload.hidden_at
  end

  test "hold_for_review! parks the report without losing the payload" do
    trash = create_trash(ai_payload: { "a" => 1 })

    trash.hold_for_review!("boom")
    trash.reload

    assert_predicate trash, :needs_review?
    assert_equal({ "a" => 1, "hold_reason" => "boom" }, trash.ai_payload)
  end

  # --- scopes ---

  test "for_heatmap only has validated, visible, sanitized reports" do
    published = create_published_trash
    create_trash # pending
    create_trash.tap { |t| t.update_columns(ai_status: "validated", severity: 3) } # validated but never sanitized
    create_published_trash.tap(&:hide!) # hidden
    create_published_trash.tap { |t| t.update_columns(ai_status: "rejected") }
    create_published_trash.tap { |t| t.update_columns(ai_status: "needs_review") }

    assert_equal [published.id], Trash.for_heatmap.pluck(:id)
  end

  test "near finds reports within the radius" do
    here = create_trash
    close = create_trash(lat: -15.7937) # about 56 m north
    far = create_trash(lat: -15.7492)   # about 5 km north

    ids = Trash.near(-47.8825, -15.7942, 100).pluck(:id)

    assert_includes ids, here.id
    assert_includes ids, close.id
    assert_not_includes ids, far.id
    assert_includes Trash.near(-47.8825, -15.7942, 6_000).pluck(:id), far.id
  end

  test "point puts longitude in x and latitude in y" do
    point = Trash.point(-47.8825, -15.7942)

    assert_in_delta(-47.8825, point.x, 1e-9)
    assert_in_delta(-15.7942, point.y, 1e-9)
  end

  # --- EXIF cross-check ---

  test "metadata_suspicious? is false without EXIF data" do
    assert_not Trash.new(taken_at: Time.utc(2026, 10, 20, 12), photo_meta: {}).metadata_suspicious?
    assert_not Trash.new(taken_at: Time.utc(2026, 10, 20, 12), photo_meta: { "exif_present" => false }).metadata_suspicious?
  end

  test "metadata_suspicious? flags an EXIF position far from the reported one" do
    taken = Time.utc(2026, 10, 20, 12)

    assert_not Trash.new(taken_at: taken, photo_meta: { "exif_distance_m" => 50 }).metadata_suspicious?
    assert_not Trash.new(taken_at: taken, photo_meta: { "exif_distance_m" => 1_000 }).metadata_suspicious?
    assert Trash.new(taken_at: taken, photo_meta: { "exif_distance_m" => 1_001 }).metadata_suspicious?
  end

  test "metadata_suspicious? flags an EXIF time far from the reported one, in either direction" do
    taken = Time.utc(2026, 10, 20, 12)
    meta = ->(offset) { { "exif_taken_at" => (taken + offset).utc.iso8601 } }

    assert_not Trash.new(taken_at: taken, photo_meta: meta.call(0)).metadata_suspicious?
    assert_not Trash.new(taken_at: taken, photo_meta: meta.call(-1.day)).metadata_suspicious? # covers any time zone offset
    assert_not Trash.new(taken_at: taken, photo_meta: meta.call(1.day)).metadata_suspicious?
    assert Trash.new(taken_at: taken, photo_meta: meta.call(-3.days)).metadata_suspicious?   # an old photo sent as new
    assert Trash.new(taken_at: taken, photo_meta: meta.call(3.days)).metadata_suspicious?
  end
end
