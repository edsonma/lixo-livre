require "test_helper"

# The JSON the pages and the app depend on. The records are stand-ins, so these run without a database:
# what is being checked is the shape, and the privacy rules (no photo address until it is protected).
class SerializersTest < ActiveSupport::TestCase
  Point = Struct.new(:x, :y)
  Person = Struct.new(:id, :name, :email)
  Photo = Struct.new(:attached) do
    def attached? = attached
    def variant(options) = "variant #{options[:resize_to_fill].join('x')}"
  end

  # answers url_for the way the controller does: an address made from what it is given
  class Urls
    def url_for(thing) = "https://lixo.test/#{thing.is_a?(String) ? thing : 'photo'}"
  end

  def report(**attrs)
    Struct.new(:id, :kind, :severity, :trash_types, :extra_info, :taken_at, :lonlat, :photo, :user, :user_id, :ai_status,
               :h3_index, :sanitized_at, :ai_payload, :ai_confidence, :created_at, :photo_meta, :hidden_at, :flags,
               keyword_init: true) do
      def pending? = ai_status == "pending"
      def published? = false
      def publishable? = false
    end.new(id: 7, kind: "dirty", severity: 60, trash_types: %w[plastic], extra_info: "bags", taken_at: Time.utc(2026, 11, 1),
            lonlat: Point.new(-47.88, -15.79), photo: Photo.new(true), user: nil, user_id: nil, ai_status: "validated",
            h3_index: "89a8100c0d3ffff", sanitized_at: Time.utc(2026, 11, 1), ai_payload: nil, ai_confidence: nil,
            created_at: Time.utc(2026, 11, 1), photo_meta: nil, hidden_at: nil, flags: [], **attrs)
  end

  # --- TrashSerializer ---

  test "a published report is sent with its position, photo and (when there is one) uploader" do
    json = TrashSerializer.call(report(user: Person.new(3, "Ana", "ana@example.com"), user_id: 3), urls: Urls.new)

    assert_equal [7, "dirty", 60, -15.79, -47.88, "https://lixo.test/photo"], json.values_at(:id, :kind, :severity, :lat, :lng, :photo_url)
    assert_equal({ id: 3, name: "Ana" }, json[:uploader]) # never the email
    assert_nil TrashSerializer.call(report, urls: Urls.new)[:uploader] # anonymous
  end

  test "collection serializes each record" do
    list = TrashSerializer.collection([report(id: 1), report(id: 2)], urls: Urls.new)

    assert_equal [1, 2], list.map { |json| json[:id] }
  end

  # --- OwnTrashSerializer ---

  test "an author sees the photo addresses once the photo is protected and still there" do
    json = OwnTrashSerializer.call(report, urls: Urls.new)

    assert_equal [true, "https://lixo.test/photo", "https://lixo.test/variant 360x360"], json.values_at(:photo_ready, :photo_url, :thumb_url)
    assert_equal ["scored", true], [json[:stage], json[:done]]
  end

  test "no photo address before the photo is protected, or after it was deleted" do
    unprotected = OwnTrashSerializer.call(report(sanitized_at: nil), urls: Urls.new)
    deleted = OwnTrashSerializer.call(report(photo: Photo.new(false)), urls: Urls.new)

    [unprotected, deleted].each do |json|
      assert_equal [false, nil, nil], json.values_at(:photo_ready, :photo_url, :thumb_url)
    end
  end

  # --- ReviewSerializer ---

  def review(trash, kind = "held")
    ReviewSerializer.call(trash, urls: Urls.new, kind: kind)
  end

  test "why a report is in the queue" do
    assert_equal "flagged", review(report, "flagged")[:reason]
    assert_equal "far_from_pin", review(report(ai_payload: { "reason" => "far_from_pin" }))[:reason]
    assert_equal "failed", review(report(ai_payload: { "hold_reason" => "timeout" }))[:reason]
    assert_equal "low_confidence", review(report(ai_confidence: 0.4))[:reason]
    assert_equal "other", review(report)[:reason]
  end

  test "a moderator sees the uploader's email, but never an unprotected photo" do
    json = review(report(user: Person.new(3, "Ana", "ana@example.com"), user_id: 3, sanitized_at: nil))

    assert_equal({ id: 3, name: "Ana", email: "ana@example.com" }, json[:uploader])
    assert_equal [false, nil], json.values_at(:photo_protected, :photo_url)
  end

  # --- FollowSerializer, NotificationSerializer, UserSerializer ---

  test "a follow without a stored cell still serializes, with empty scores" do
    follow = Struct.new(:h3_index, :created_at).new("89a8100c0d3ffff", Time.utc(2026, 11, 2))
    cell = Struct.new(:score, :lonlat).new(41.26, Point.new(-47.9, -15.8))

    assert_equal [41.3, -15.8, -47.9], FollowSerializer.call(follow, cells: { "89a8100c0d3ffff" => cell }).values_at(:score, :lat, :lng)
    assert_equal [nil, nil, nil], FollowSerializer.call(follow, cells: {}).values_at(:score, :lat, :lng)
  end

  test "a notification rounds its scores and says whether it was read" do
    note = Struct.new(:id, :kind, :h3_index, :score, :previous_score, :lat, :lng, :read_at, :created_at)
                 .new(1, "worse", "89a8100c0d3ffff", 52.349, 30.0, -15.8, -47.9, nil, Time.utc(2026, 11, 3))

    json = NotificationSerializer.call(note)

    assert_equal [52.3, 30.0, false], json.values_at(:score, :previous_score, :read)
  end

  test "a person is sent without any secret" do
    user = Struct.new(:id, :name, :email, :role, :provider, :passkeys) do
      def admin? = false
      def privileged? = false
      def terms_current? = true
      def email_verified? = true
      def otp_enabled? = false
    end.new(1, "Ana", "ana@example.com", "user", "google", [1, 2])

    json = UserSerializer.call(user)

    assert_equal [2, true], json.values_at(:passkeys, :google)
    assert_empty json.keys & %i[encrypted_password otp_secret otp_recovery_codes]
  end
end
