class User < ApplicationRecord
  enum :role, { user: 0, moderator: 1, admin: 2 }, default: :user

  has_many :devices, dependent: :nullify
  has_many :trashes, dependent: :nullify

  validates :email, presence: true, uniqueness: true
end
