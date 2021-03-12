require_relative 'lib/ears/version'

Gem::Specification.new do |spec|
  spec.name = 'ears'
  spec.version = Ears::VERSION
  spec.authors = ['Mario Mainz']
  spec.email = ['mario.mainz@invision.de']

  spec.summary = 'A gem for building RabbitMQ consumers.'
  spec.description = 'A gem for building RabbitMQ consumers.'
  spec.homepage = 'https://github.com/ivx/ears'
  spec.license = 'MIT'
  spec.required_ruby_version = Gem::Requirement.new('>= 2.5.0')

  spec.metadata['allowed_push_host'] = "TODO: Set to 'http://mygemserver.com'"

  spec.metadata['homepage_uri'] = spec.homepage
  spec.metadata['source_code_uri'] = 'https://github.com/ivx/ears'
  spec.metadata['changelog_uri'] =
    'https://github.com/ivx/ears/blob/master/CHANGELOG.md'

  spec.files =
    Dir.chdir(File.expand_path('..', __FILE__)) do
      `git ls-files -z`.split("\x0").reject do |f|
        f.match(%r{^(test|spec|features)/})
      end
    end
  spec.bindir = 'exe'
  spec.executables = spec.files.grep(%r{^exe/}) { |f| File.basename(f) }
  spec.require_paths = ['lib']

  spec.add_dependency 'bunny'
end
