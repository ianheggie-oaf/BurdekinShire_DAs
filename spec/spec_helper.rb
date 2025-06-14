# frozen_string_literal: true

require "bundler/setup"
require "dotenv/load"
require "webmock/rspec"
require "vcr"
require_relative "../scraper"
require_relative "support/webmock_burdekin_fixtures"

RSpec.configure do |config|
  # Enable flags like --only-failures and --next-failure
  config.example_status_persistence_file_path = ".rspec_status"

  # Make it stop on the first failure. Makes in this case
  # for quicker debugging
  config.fail_fast = !ENV["FAIL_FAST"].to_s.empty?

  # Disable RSpec exposing methods globally on `Module` and `main`
  config.disable_monkey_patching!

  config.expect_with :rspec do |c|
    c.syntax = :expect
  end
end

VCR.configure do |c|
  c.cassette_library_dir = "spec/cassettes"
  c.hook_into :webmock
  c.configure_rspec_metadata!
end
