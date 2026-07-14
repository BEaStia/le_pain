lib = File.expand_path('lib', __dir__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'le_pain/version'

Gem::Specification.new do |spec|
  spec.name          = 'le_pain'
  spec.version       = LePain::VERSION
  spec.authors       = ['Igor Pavlov']
  spec.email         = ['gophan1992@gmail.com']

  spec.summary       = 'A micro framework for building Ruby microservices.'
  spec.description   = 'LePain is a lightweight framework for fast development of microservices in Ruby with environment management, configuration, graceful shutdown, and health checks.'
  spec.homepage      = 'https://github.com/beastia/le_pain'
  spec.license       = 'MIT'

  spec.required_ruby_version = '>= 3.0.0'

  spec.metadata['homepage_uri'] = spec.homepage
  spec.metadata['source_code_uri'] = spec.homepage
  spec.metadata['rubygems_mfa_required'] = 'true'

  spec.files = `git ls-files -z`.split("\x0").reject do |f|
    f.match(%r{^(test|spec|features)/})
  end
  spec.bindir        = 'exe'
  spec.executables   = spec.files.grep(%r{^exe/}) { |f| File.basename(f) }
  spec.require_paths = ['lib']

  spec.add_dependency 'logger', '~> 1.6'
  spec.add_dependency 'brotli', '~> 0.6'

  spec.add_development_dependency 'bundler', '~> 2.0'
  spec.add_development_dependency 'rake', '~> 13.0'
  spec.add_development_dependency 'rspec', '~> 3.12'
  spec.add_development_dependency 'sqlite3', '~> 2.0'
end
