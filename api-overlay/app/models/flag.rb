class Flag < ApplicationRecord
  REASONS = %w[not_trash privacy inappropriate duplicate wrong_location].freeze
  AUTO_HIDE_THRESHOLD = 3 # pending flags that hide a photo until a moderator looks

  belongs_to :trash
  belongs_to :device

  enum :status, { pending: "pending", resolved: "resolved", dismissed: "dismissed" }, default: "pending"

  validates :reason, inclusion: { in: REASONS }
  validates :device_id, uniqueness: { scope: :trash_id }

  after_create_commit :auto_hide_trash

  private

  def auto_hide_trash
    trash.hide! if trash.flags.pending.count >= AUTO_HIDE_THRESHOLD && trash.hidden_at.nil?
  end
end
