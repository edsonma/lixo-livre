class CreateFlags < ActiveRecord::Migration[8.0]
  def change
    create_table :flags do |t|
      t.references :trash, null: false, foreign_key: true
      t.references :device, null: false, foreign_key: true
      t.string :reason, null: false
      t.string :status, null: false, default: "pending"
      t.timestamps
    end

    add_index :flags, [:trash_id, :device_id], unique: true # one flag per device per photo
  end
end
