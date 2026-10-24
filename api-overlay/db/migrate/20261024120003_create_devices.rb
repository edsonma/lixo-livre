class CreateDevices < ActiveRecord::Migration[8.0]
  def change
    # Anonymous identity for the mobile app: the phone stores `token` and sends it as X-Device-Token
    create_table :devices do |t|
      t.string :token, null: false
      t.references :user, null: true, foreign_key: true
      t.datetime :last_seen_at
      t.timestamps
    end
    add_index :devices, :token, unique: true
  end
end
