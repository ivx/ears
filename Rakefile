# frozen_string_literal: true

require 'rake/clean'
require 'bundler/gem_tasks'
require 'rubocop'
require 'rubocop/rake_task'
require 'rspec/core/rake_task'
require 'yard'

CLEAN << '.yardoc'
CLOBBER << 'doc' << 'coverage'

RSpec::Core::RakeTask.new(:spec)
YARD::Rake::YardocTask.new { |t| t.stats_options = %w[--list-undoc] }

RuboCop::RakeTask.new(:rubocop) do |task|
  task.formatters = ['simple']
  task.fail_on_error = true
end

desc 'Run Prettier'
task(:prettier) { sh 'npm run lint' }

task default: %i[spec rubocop prettier]
