class CreateUsers < ActiveRecord::Migration[8.0]
  def change
    # Minimal for now: login comes later (Rails 8 `rails g authentication` can add password_digest)
    create_table :users do |t|
      t.string  :email, null: false
      t.string  :name
      t.integer :role, null: false, default: 0 # user / moderator / admin
      t.timestamps
    end
    add_index :users, :email, unique: true
  end
end
