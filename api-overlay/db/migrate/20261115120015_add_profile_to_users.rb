# What a person can say about themselves: a short bio, a website and a gender (private). The profile
# picture is an Active Storage attachment (User#avatar), so it has no column.
class AddProfileToUsers < ActiveRecord::Migration[8.0]
  def change
    add_column :users, :bio, :string, limit: 160 unless column_exists?(:users, :bio)
    add_column :users, :website, :string, limit: 200 unless column_exists?(:users, :website)
    add_column :users, :gender, :string, limit: 20 unless column_exists?(:users, :gender)
  end
end
