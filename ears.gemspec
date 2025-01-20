require_relative 'lib/ears/version'

Gem::Specification.new do |spec|
  spec.name = 'ears'
  spec.version = Ears::VERSION
  spec.authors = ['InVision AG']
  spec.email = ['johannes.luedke@invision.de']

  spec.summary = 'A gem for building RabbitMQ consumers.'
  spec.description = 'A gem for building RabbitMQ consumers.'
  spec.homepage = 'https://github.com/ivx/ears'
  spec.license = 'MIT'
  spec.required_ruby_version = Gem::Requirement.new('>= 3.0.7')

  spec.metadata['allowed_push_host'] = 'https://rubygems.org'

  # Disabled for automatic relase on GH action
  spec.metadata['rubygems_mfa_required'] = 'false' # rubocop:disable Gemspec/RequireMFA

  spec.metadata['homepage_uri'] = spec.homepage
  spec.metadata['source_code_uri'] = 'https://github.com/ivx/ears'
  spec.metadata[
    'changelog_uri'
  ] = 'https://github.com/ivx/ears/blob/main/CHANGELOG.md'

  spec.files =
    Dir.chdir(File.expand_path('..', __FILE__)) do
      `git ls-files -z`.split("\x0")
        .reject { |f| f.match(%r{^(test|spec|features)/}) }
    end
  spec.bindir = 'exe'
  spec.executables = spec.files.grep(%r{^exe/}) { |f| File.basename(f) }
  spec.require_paths = ['lib']

  spec.add_dependency 'bunny', '>= 2.22.0'
  spec.add_dependency 'multi_json'
end
