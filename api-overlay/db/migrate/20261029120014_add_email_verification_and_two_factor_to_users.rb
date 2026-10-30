# Email verification (Resend) and optional two-factor login (TOTP).
# Accounts that already exist are treated as verified: they signed up before emails existed.
class AddEmailVerificationAndTwoFactorToUsers < ActiveRecord::Migration[8.0]
  def up
    unless column_exists?(:users, :email_verified_at)
      add_column :users, :email_verified_at, :datetime
      execute "UPDATE users SET email_verified_at = NOW() WHERE email_verified_at IS NULL"
    end
    add_column :users, :otp_secret, :string unless column_exists?(:users, :otp_secret)             # encrypted, see OtpVault
    add_column :users, :otp_enabled_at, :datetime unless column_exists?(:users, :otp_enabled_at)    # nil while only set up, not confirmed
    add_column :users, :otp_last_step, :bigint unless column_exists?(:users, :otp_last_step)        # blocks reusing a code
    add_column :users, :otp_recovery_codes, :text unless column_exists?(:users, :otp_recovery_codes) # JSON list of digests
  end

  def down
    %i[email_verified_at otp_secret otp_enabled_at otp_last_step otp_recovery_codes].each do |c|
      remove_column :users, c if column_exists?(:users, c)
    end
  end
end
