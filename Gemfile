source 'https://rubygems.org'

gemspec

group :test do
  gem 'parallel', '< 2.0' # 2.x drops Ruby 3.2 support (gemspec still requires >= 3.2.9)
  gem 'rake'
  gem 'rspec'
  gem 'rubocop', require: false
  gem 'rubocop-rake', require: false
  gem 'rubocop-rspec', require: false
  gem 'simplecov'
  gem 'syntax_tree', require: false
  gem 'yard', require: false
end
