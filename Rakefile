# frozen_string_literal: true

require 'rake/clean'
require 'bundler/gem_tasks'
require 'rspec/core/rake_task'
require 'yard'

CLEAN << '.yardoc'
CLOBBER << 'doc'
CLOBBER << 'coverage'

RSpec::Core::RakeTask.new(:spec)
YARD::Rake::YardocTask.new { |t| t.stats_options = %w[--list-undoc] }

task default: :spec
