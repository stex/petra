$:.push File.expand_path('../lib', __FILE__)

# Maintain your gem's version:
require 'petra/version'

# Describe your gem and declare its dependencies:
Gem::Specification.new do |s|
  s.name        = "petra"
  s.version     = Petra::VERSION
  s.authors     = ['Stefan Exner']
  s.email       = ['stex@sterex.de']
  s.homepage    = 'https://www.github.com/stex/petra'
  s.summary     = 'Temporarily persisted transactions'
  s.description = 'Temporarily persisted transactions'
  s.license     = 'MIT'

  s.files = Dir["{app,config,db,lib}/**/*", "MIT-LICENSE", "Rakefile", "README.rdoc"]
  s.test_files = Dir['test/**/*', 'spec/**/*']

  s.add_dependency 'rails', '~> 4.2'
  s.add_dependency 'require_all', '~> 1.3'

  s.add_development_dependency 'sqlite3'
  s.add_development_dependency 'temping'
  s.add_development_dependency 'rspec-rails'
  s.add_development_dependency 'pry-rails'
  s.add_development_dependency 'guard-rspec'
  s.add_development_dependency 'guard-rubocop'
end
