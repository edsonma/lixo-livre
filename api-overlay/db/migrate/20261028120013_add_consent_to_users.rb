# Consent to the Terms of Use and the Privacy Policy: when, and which version of the text.
class AddConsentToUsers < ActiveRecord::Migration[8.0]
  def change
    add_column :users, :consented_at, :datetime unless column_exists?(:users, :consented_at)
    add_column :users, :terms_version, :string unless column_exists?(:users, :terms_version)
  end
end
