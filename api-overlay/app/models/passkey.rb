# A WebAuthn credential: the public half of a key that lives in the phone's secure hardware and is
# unlocked with a fingerprint or face. The server never sees the biometric, only a signature.
class Passkey < ApplicationRecord
  belongs_to :user

  validates :external_id, :public_key, presence: true
  validates :external_id, uniqueness: true
end
