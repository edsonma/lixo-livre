class Follow < ApplicationRecord
  H3_FORMAT = /\A[0-9a-f]{15}\z/
  MAX_PER_USER = 50

  belongs_to :user

  validates :h3_index, format: { with: H3_FORMAT }, uniqueness: { scope: :user_id }
  validate :not_too_many, on: :create

  # Starts following with the cell as it is now, so only changes from here on are announced.
  def self.start(user, h3_index)
    cell = HeatCell.find_by(h3_index: h3_index, resolution: Trash::H3_RESOLUTION)
    find_or_initialize_by(user: user, h3_index: h3_index).tap do |follow|
      follow.last_score = cell&.score || 0 if follow.new_record?
      follow.last_cleaned_at = cell&.cleaned_at if follow.new_record?
      follow.save!
    end
  end

  private

  def not_too_many
    errors.add(:base, "too many followed places") if user && user.follows.count >= MAX_PER_USER
  end
end
