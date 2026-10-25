require "test_helper"
require "open3"

# bin/check_database_url runs before Rails boots in production (bin/railway-start).
class CheckDatabaseUrlTest < ActiveSupport::TestCase
  SCRIPT = Rails.root.join("bin/check_database_url").to_s
  GOOD = "postgres://postgres:abc123@postgis.railway.internal:5432/lixo_livre".freeze

  def check(url)
    stdout, stderr, status = Open3.capture3({ "DATABASE_URL" => url }, RbConfig.ruby, SCRIPT)
    [stdout.strip, stderr, status.success?]
  end

  test "accepts a good URL and prints it back" do
    out, _err, ok = check(GOOD)

    assert ok
    assert_equal GOOD, out
  end

  test "accepts postgresql:// and an encoded password" do
    assert check("postgresql://u:p%40ss%23@host.internal:5432/db").last
  end

  test "cleans surrounding spaces and quotes" do
    out, _err, ok = check(%( "#{GOOD}" ))

    assert ok
    assert_equal GOOD, out
  end

  test "rejects a Railway reference that was not filled in, and shows which one" do
    _out, err, ok = check("postgres://postgres:${{postgis.POSTGRES_PASSWORD}}@postgis.railway.internal:5432/lixo_livre")

    assert_not ok
    assert_includes err, "${{postgis.POSTGRES_PASSWORD}}"
    assert_includes err, "service name"
  end

  test "rejects a password with special characters, without printing it" do
    ["p@ss#word", "p/ss", "p?ss", "pa ss"].each do |password|
      _out, err, ok = check("postgres://postgres:#{password}@postgis.railway.internal:5432/lixo_livre")

      assert_not ok, password
      assert_not_includes err, password, "the password must never be printed"
      assert_includes err, "password hidden"
    end
  end

  test "rejects a missing host, missing database name, wrong scheme and empty value" do
    [
      "postgres://postgres:abc@:5432/lixo_livre",
      "postgres://postgres:abc@postgis.railway.internal:5432",
      "http://postgres:abc@postgis.railway.internal:5432/lixo_livre",
      "postgres://postgres:abc@postgis.railway.internal:99999/lixo_livre",
      ""
    ].each { |url| assert_not check(url).last, url.inspect }
  end

  test "a URL without // after the scheme is explained, not a crash" do
    ["postgres:postgres:abc@postgis.railway.internal:5432/lixo_livre", "postgres:abc", "postgres:", "mailto:a@b.c"].each do |url|
      out, err, ok = check(url)

      assert_not ok, url
      assert_empty out
      assert_not_includes err, "NoMethodError"
      assert_not_includes err, "abc@" if url.include?("abc@")
    end
    assert_includes check("postgres:postgres:abc@host:5432/db")[1], "//"
  end

  test "garbage in never makes the script crash" do
    ["", " ", "\n", "://", "postgres://", "postgres://@", "postgres://:@/", "%%%", "a b c", "postgres://[::1", "postgres://user:pw@host:99999999/db", "\u00e9\u00e8"].each do |url|
      _out, err, _ok = check(url)

      assert_not_includes err, "Error)", url.inspect # no Ruby backtrace
      assert_not_includes err, "from bin/check_database_url"
    end
  end

  test "the error always suggests the PG* variables as the way out" do
    _out, err, _ok = check("nonsense")

    assert_includes err, "PGHOST"
  end
end
