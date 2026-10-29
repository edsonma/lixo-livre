require "test_helper"

class DatabaseBackupTest < ActiveSupport::TestCase
  Page = Struct.new(:contents, :is_truncated, :next_continuation_token)
  Obj = Struct.new(:key)

  class FakeS3
    attr_reader :objects, :deleted

    def initialize(keys = [])
      @objects = keys.to_h { |k| [k, "x"] }
      @deleted = []
    end

    def put_object(bucket:, key:, body:)
      @objects[key] = body.read
    end

    def list_objects_v2(bucket:, prefix:, continuation_token: nil)
      Page.new(@objects.keys.select { |k| k.start_with?(prefix) }.map { |k| Obj.new(k) }, false, nil)
    end

    def delete_objects(bucket:, delete:)
      delete[:objects].each { |o| @deleted << o[:key]; @objects.delete(o[:key]) }
    end
  end

  NOW = Time.utc(2026, 10, 29, 3, 0, 0)

  def backup(s3, keep: 3, dump: ->(path) { File.write(path, "DUMP") })
    DatabaseBackup.new(client: s3, bucket: "b", prefix: "db", keep: keep, dump: dump, clock: -> { NOW })
  end

  test "uploads the dump under a dated name" do
    s3 = FakeS3.new
    key = backup(s3).run

    assert_equal "db/lixo-livre-20261029-030000.dump", key
    assert_equal "DUMP", s3.objects[key]
  end

  test "keeps only the newest copies" do
    old = %w[20261020 20261021 20261022 20261023].map { |d| "db/lixo-livre-#{d}-030000.dump" }
    s3 = FakeS3.new(old + ["db/notes.txt"])

    backup(s3, keep: 3).run

    assert_equal old.first(2).sort, s3.deleted.sort # 4 old + 1 new = 5, keep 3
    assert_includes s3.objects.keys, "db/notes.txt"
  end

  test "an empty dump is a failure and nothing is uploaded or deleted" do
    s3 = FakeS3.new(["db/lixo-livre-20261020-030000.dump"])
    assert_raises(DatabaseBackup::Failed) { backup(s3, dump: ->(path) { File.write(path, "") }).run }
    assert_empty s3.deleted
    assert_equal 1, s3.objects.size
  end

  test "needs a bucket" do
    assert_raises(DatabaseBackup::Failed) { DatabaseBackup.from_env({}) }
  end
end
