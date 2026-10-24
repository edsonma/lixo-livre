class Device < ApplicationRecord
  belongs_to :user, optional: true
  has_many :trashes, dependent: :restrict_with_error
  has_many :flags, dependent: :destroy

  has_secure_token :token

  # Call this when login is added: the person keeps their anonymous history.
  def claim_by!(user)
    transaction do
      update!(user: user)
      trashes.update_all(user_id: user.id)
    end
  end
end
