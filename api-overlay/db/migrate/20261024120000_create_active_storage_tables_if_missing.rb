# Active Storage's own tables, kept here with a fixed version number.
# (Named differently from the generated migration on purpose, so both can exist in a local app.)
#
# Do NOT run `bin/rails active_storage:install`: it writes a migration stamped with the current
# time, so every Docker build got a new version number and tried to create the tables again
# ("PG::DuplicateTable: relation active_storage_blobs already exists").
#
# The guards make it safe on a database that already has these tables from such an install.
class CreateActiveStorageTablesIfMissing < ActiveRecord::Migration[8.0]
  def up
    unless table_exists?(:active_storage_blobs)
      create_table :active_storage_blobs do |t|
        t.string   :key,          null: false
        t.string   :filename,     null: false
        t.string   :content_type
        t.text     :metadata
        t.string   :service_name, null: false
        t.bigint   :byte_size,    null: false
        t.string   :checksum
        t.datetime :created_at,   null: false, precision: 6
        t.index [ :key ], unique: true
      end
    end

    unless table_exists?(:active_storage_attachments)
      create_table :active_storage_attachments do |t|
        t.string     :name,   null: false
        t.references :record, null: false, polymorphic: true, index: false
        t.references :blob,   null: false
        t.datetime   :created_at, null: false, precision: 6
        t.index [ :record_type, :record_id, :name, :blob_id ], name: :index_active_storage_attachments_uniqueness, unique: true
        t.foreign_key :active_storage_blobs, column: :blob_id
      end
    end

    unless table_exists?(:active_storage_variant_records)
      create_table :active_storage_variant_records do |t|
        t.belongs_to :blob, null: false, index: false
        t.string :variation_digest, null: false
        t.index [ :blob_id, :variation_digest ], name: :index_active_storage_variant_records_uniqueness, unique: true
        t.foreign_key :active_storage_blobs, column: :blob_id
      end
    end
  end

  def down
    drop_table :active_storage_variant_records, if_exists: true
    drop_table :active_storage_attachments, if_exists: true
    drop_table :active_storage_blobs, if_exists: true
  end
end
