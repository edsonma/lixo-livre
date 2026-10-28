class Notification < ApplicationRecord
  KINDS = %w[worse cleaned].freeze

  belongs_to :user

  validates :kind, inclusion: { in: KINDS }
  validates :h3_index, presence: true

  scope :unread, -> { where(read_at: nil) }
  scope :newest, -> { order(created_at: :desc, id: :desc) }
end
