require "test_helper"

# Production eager-loads every file in app/ at boot. A file whose name does not match the constant it
# defines (openai.rb defining OpenAI, say) passes in development and crashes the deploy.
class ZeitwerkTest < ActiveSupport::TestCase
  test "every file under app defines the constant its name implies" do
    Rails.autoloaders.main.eager_load(force: true)
  end
end
