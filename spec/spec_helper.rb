# frozen_string_literal: true

require 'rspec/core'
require 'simplecov'
require 'ears'

SimpleCov.start do
  enable_coverage :branch
  primary_coverage :branch
end

RSpec.configure(&:disable_monkey_patching!)

if RSpec.configuration.files_to_run.length > 1
  # Let's increase this later on
  SimpleCov.minimum_coverage line: 97.5, branch: 65.7
end
