# Plain Minitest, no Rails needed:  ruby tools/test/patch_generated_app_test.rb
require "minitest/autorun"
require "tmpdir"
require "fileutils"
require "open3"
require "rbconfig"

class PatchGeneratedAppTest < Minitest::Test
  SCRIPT = File.expand_path("../patch_generated_app.rb", __dir__)

  # What `rails new --api -d postgresql` generates, trimmed to what matters here.
  DATABASE_YML = <<~YML
    default: &default
      adapter: postgresql
      encoding: unicode
      max_connections: <%= ENV.fetch("RAILS_MAX_THREADS") { 5 } %>

    development:
      <<: *default
      database: api_development
  YML
  BOOT_RB = <<~RUBY
    ENV["BUNDLE_GEMFILE"] ||= File.expand_path("../Gemfile", __dir__)

    require "bundler/setup" # Set up gems listed in the Gemfile.
  RUBY

  def with_app(database_yml: DATABASE_YML, boot_rb: BOOT_RB)
    Dir.mktmpdir do |dir|
      FileUtils.mkdir_p(File.join(dir, "config"))
      File.write(File.join(dir, "config", "database.yml"), database_yml) if database_yml
      File.write(File.join(dir, "config", "boot.rb"), boot_rb) if boot_rb
      yield dir
    end
  end

  def patch(dir)
    Open3.capture3(RbConfig.ruby, SCRIPT, dir)
  end

  def read(dir, name)
    File.read(File.join(dir, "config", name))
  end

  # Runs a patched boot.rb up to its DATABASE_URL rewrite and returns the resulting value.
  def database_url_after_boot(dir, url)
    snippet = read(dir, "boot.rb").split("ENV[\"BUNDLE_GEMFILE\"]").first
    env = url ? { "DATABASE_URL" => url } : {}
    out, = Open3.capture2(env, RbConfig.ruby, "-e", "#{snippet}\nputs ENV['DATABASE_URL'].inspect")
    out.strip
  end

  def test_switches_the_adapter_to_postgis
    with_app do |dir|
      _, err, status = patch(dir)

      assert status.success?, err
      assert_includes read(dir, "database.yml"), "adapter: postgis"
      refute_includes read(dir, "database.yml"), "adapter: postgresql"
      assert_includes read(dir, "database.yml"), "encoding: unicode" # the rest is untouched
    end
  end

  def test_puts_the_rewrite_before_the_rest_of_boot_rb
    with_app do |dir|
      patch(dir)
      boot = read(dir, "boot.rb")

      assert boot.index("DATABASE_URL") < boot.index("BUNDLE_GEMFILE"), "must run before Bundler and Rails load"
      assert_includes boot, 'require "bundler/setup"'
    end
  end

  def test_running_twice_changes_nothing_the_second_time
    with_app do |dir|
      patch(dir)
      first = [read(dir, "database.yml"), read(dir, "boot.rb")]
      out, err, status = patch(dir)

      assert status.success?, err
      assert_equal first, [read(dir, "database.yml"), read(dir, "boot.rb")]
      assert_includes out, "already"
      assert_equal 1, read(dir, "boot.rb").scan("lixo-livre: DATABASE_URL scheme").size
    end
  end

  def test_rewrites_postgres_urls_to_postgis
    with_app do |dir|
      patch(dir)

      assert_equal '"postgis://u:p@host:5432/db"', database_url_after_boot(dir, "postgresql://u:p@host:5432/db")
      assert_equal '"postgis://u:p@host:5432/db"', database_url_after_boot(dir, "postgres://u:p@host:5432/db")
    end
  end

  def test_leaves_other_urls_alone
    with_app do |dir|
      patch(dir)

      assert_equal '"postgis://u:p@host/db"', database_url_after_boot(dir, "postgis://u:p@host/db")
      assert_equal '"mysql2://u:p@host/db"', database_url_after_boot(dir, "mysql2://u:p@host/db")
      assert_equal "nil", database_url_after_boot(dir, nil)
    end
  end

  def test_does_not_touch_a_password_that_contains_postgres
    with_app do |dir|
      patch(dir)

      assert_equal '"postgis://u:postgres://x@host/db"', database_url_after_boot(dir, "postgresql://u:postgres://x@host/db")
    end
  end

  def test_fails_clearly_when_it_is_not_a_generated_app
    with_app(database_yml: nil, boot_rb: nil) do |dir|
      _, err, status = patch(dir)

      refute status.success?
      assert_match(/not found/, err)
    end
  end

  def test_fails_clearly_when_the_adapter_line_is_missing
    with_app(database_yml: "default:\n  adapter: sqlite3\n") do |dir|
      _, err, status = patch(dir)

      refute status.success?
      assert_match(/adapter: postgresql/, err)
    end
  end
end
