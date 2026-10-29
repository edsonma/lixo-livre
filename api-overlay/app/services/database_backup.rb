require "open3"
require "tmpdir"

# A compressed copy of the database (pg_dump -Fc) uploaded to an S3-compatible bucket (Cloudflare R2,
# Backblaze B2, AWS...), keeping only the newest BACKUP_KEEP copies. Run it on a schedule:
#
#   bin/rails db:backup
#
#   BACKUP_BUCKET      bucket for the copies (use a different one from the photos)
#   BACKUP_PREFIX      folder inside the bucket                      (default "db/")
#   BACKUP_KEEP        how many copies to keep                       (default 14)
#   S3_REGION, S3_ACCESS_KEY_ID, S3_SECRET_ACCESS_KEY, S3_ENDPOINT   the same credentials as the photos
#
# Restore:  pg_restore --clean --if-exists --no-owner -d "$DATABASE_URL" lixo-livre-YYYYmmdd-HHMMSS.dump
class DatabaseBackup
  class Failed < StandardError; end

  DEFAULT_KEEP = 14

  # client: an Aws::S3::Client (anything with put_object, list_objects_v2, delete_objects)
  # dump:   ->(path) { runs pg_dump into that file }, replaceable in tests
  def initialize(client:, bucket:, prefix: "db/", keep: DEFAULT_KEEP, dump: method(:pg_dump), clock: -> { Time.now.utc })
    @client = client
    @bucket = bucket
    @prefix = prefix.to_s.empty? || prefix.end_with?("/") ? prefix.to_s : "#{prefix}/"
    @keep = [keep.to_i, 1].max
    @dump = dump
    @clock = clock
  end

  def self.from_env(env = ENV)
    bucket = env["BACKUP_BUCKET"].to_s.strip
    raise Failed, "BACKUP_BUCKET is not set" if bucket.empty?

    require "aws-sdk-s3"
    options = { region: env["S3_REGION"].presence || "auto", access_key_id: env["S3_ACCESS_KEY_ID"], secret_access_key: env["S3_SECRET_ACCESS_KEY"] }
    options[:endpoint] = env["S3_ENDPOINT"] if env["S3_ENDPOINT"].present?
    options[:force_path_style] = true if env["S3_ENDPOINT"].present?
    new(client: Aws::S3::Client.new(**options), bucket: bucket, prefix: env["BACKUP_PREFIX"].presence || "db/",
        keep: env["BACKUP_KEEP"].presence || DEFAULT_KEEP)
  end

  # Returns the key it uploaded.
  def run
    key = "#{@prefix}lixo-livre-#{@clock.call.strftime('%Y%m%d-%H%M%S')}.dump"
    Dir.mktmpdir("backup") do |dir|
      path = File.join(dir, "db.dump")
      @dump.call(path)
      raise Failed, "pg_dump produced an empty file" unless File.size?(path)

      File.open(path, "rb") { |file| @client.put_object(bucket: @bucket, key: key, body: file) }
    end
    prune
    key
  end

  # Deletes all but the newest @keep copies (names sort by date).
  def prune
    keys = []
    token = nil
    loop do
      page = @client.list_objects_v2(bucket: @bucket, prefix: @prefix, continuation_token: token)
      keys.concat(page.contents.map(&:key).grep(/\.dump\z/))
      break unless page.is_truncated

      token = page.next_continuation_token
    end
    old = keys.sort.reverse.drop(@keep)
    return [] if old.empty?

    @client.delete_objects(bucket: @bucket, delete: { objects: old.map { |k| { key: k } } })
    old
  end

  private

  def pg_dump(path)
    url = ENV["DATABASE_URL"].to_s
    args = ["pg_dump", "--format=custom", "--no-owner", "--file", path]
    args << url unless url.empty? # otherwise pg_dump uses PGHOST, PGUSER, PGPASSWORD, PGDATABASE
    _out, err, status = Open3.capture3(*args)
    raise Failed, "pg_dump failed: #{err.to_s.strip[0, 300]}" unless status.success?
  end
end
