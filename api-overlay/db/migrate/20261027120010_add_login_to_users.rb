# Login: Devise's password column, the Google identity, a stable WebAuthn user handle, and passkeys.
# Every step is guarded so it is safe on a database that already has part of it.
class AddLoginToUsers < ActiveRecord::Migration[8.0]
  def change
    add_column :users, :encrypted_password, :string, null: false, default: "" unless column_exists?(:users, :encrypted_password)
    add_column :users, :provider, :string unless column_exists?(:users, :provider)
    add_column :users, :uid, :string unless column_exists?(:users, :uid)
    add_column :users, :webauthn_id, :string unless column_exists?(:users, :webauthn_id)
    add_column :users, :last_sign_in_at, :datetime unless column_exists?(:users, :last_sign_in_at)

    unless index_exists?(:users, %i[provider uid])
      add_index :users, %i[provider uid], unique: true, where: "provider IS NOT NULL", name: "index_users_on_provider_and_uid"
    end
    add_index :users, :webauthn_id, unique: true unless index_exists?(:users, :webauthn_id)

    unless table_exists?(:passkeys)
      create_table :passkeys do |t|
        t.references :user, null: false, foreign_key: true
        t.string  :external_id, null: false # the credential id, base64url
        t.text    :public_key, null: false
        t.bigint  :sign_count, null: false, default: 0
        t.string  :nickname
        t.datetime :last_used_at
        t.timestamps
      end
      add_index :passkeys, :external_id, unique: true
    end
  end
end
