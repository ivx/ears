source 'https://rubygems.org'

gemspec

group :test do
  # @prettier/plugin-ruby's vendored server.rb still calls JSON.fast_generate,
  # removed in json 3.0 (https://github.com/ruby/json/releases/tag/v3.0.0).
  # Remove this pin once https://github.com/prettier/plugin-ruby/pull/1468 merges and ships.
  gem 'json', '< 3'
  gem 'rake'
  gem 'rspec'
  gem 'rubocop', require: false
  gem 'rubocop-rake', require: false
  gem 'rubocop-rspec', require: false
  gem 'simplecov'
  gem 'syntax_tree', require: false
  gem 'yard', require: false
end
