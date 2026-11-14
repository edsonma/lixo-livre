class Flag < ApplicationRecord
  REASONS = %w[not_trash privacy inappropriate duplicate wrong_location].freeze
  AUTO_HIDE_THRESHOLD = 3 # people (logged-in accounts) whose pending flags hide a photo until a moderator looks

  belongs_to :trash
  belongs_to :device

  enum :status, { pending: "pending", resolved: "resolved", dismissed: "dismissed" }, default: "pending"

  validates :reason, inclusion: { in: REASONS }
  validates :device_id, uniqueness: { scope: :trash_id }

  after_create_commit :auto_hide_trash

  private

  # Anyone can create devices (and so flags) for free, so three anonymous flags would let a single person
  # take down any photo. Only distinct accounts count towards hiding; every flag still reaches the moderators.
  def auto_hide_trash
    return unless trash.hidden_at.nil?

    people = trash.flags.pending.joins(:device).where.not(devices: { user_id: nil }).distinct.count("devices.user_id")
    trash.hide! if people >= AUTO_HIDE_THRESHOLD
  end
end
