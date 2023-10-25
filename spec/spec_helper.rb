require 'bundler/setup'
require 'simplecov'

SimpleCov.start do
  enable_coverage :branch
  primary_coverage :branch
end
if RSpec.configuration.files_to_run.length > 1
  # Let's increase this later on
  SimpleCov.minimum_coverage line: 97.5, branch: 65.7
end

RSpec.configure do |config|
  # Enable flags like --only-failures and --next-failure
  config.example_status_persistence_file_path = '.rspec_status'

  # Disable RSpec exposing methods globally on `Module` and `main`
  config.disable_monkey_patching!

  config.expect_with :rspec do |c|
    c.syntax = :expect
  end
end
