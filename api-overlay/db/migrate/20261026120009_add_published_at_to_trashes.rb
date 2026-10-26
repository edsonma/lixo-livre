# A report is now scored by the AI first and only appears on the map after its author taps
# "Publicar" (published_at). Reports that were already validated before this step existed stay on
# the map: they are marked as published when they were validated.
class AddPublishedAtToTrashes < ActiveRecord::Migration[8.0]
  def up
    add_column :trashes, :published_at, :datetime unless column_exists?(:trashes, :published_at)
    add_index :trashes, :published_at unless index_exists?(:trashes, :published_at)
    execute "UPDATE trashes SET published_at = COALESCE(validated_at, created_at) WHERE ai_status = 'validated' AND published_at IS NULL"
  end

  def down
    remove_index :trashes, :published_at if index_exists?(:trashes, :published_at)
    remove_column :trashes, :published_at if column_exists?(:trashes, :published_at)
  end
end
