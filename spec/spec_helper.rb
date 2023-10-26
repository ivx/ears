# frozen_string_literal: true

require 'simplecov'
SimpleCov.start do
  enable_coverage :branch
  primary_coverage :branch
end

require 'rspec/core'
require 'ears'

RSpec.configure(&:disable_monkey_patching!)

if RSpec.configuration.files_to_run.length > 1
  # Let's increase this later on
  SimpleCov.minimum_coverage line: 97.4, branch: 62.8
end
