# -*- encoding: utf-8 -*-
require File.join(File.dirname(__FILE__), "lib", "state_jacket", "version")

Gem::Specification.new do |gem|
  gem.name          = "state_jacket"
  gem.license       = "MIT"
  gem.version       = StateJacket::VERSION
  gem.authors       = ["Nathan Hopkins"]
  gem.email         = ["natehop@gmail.com"]
  gem.summary       = "A simple & intuitive state machine"
  gem.homepage      = "https://github.com/hopsoft/state_jacket"

  gem.files         = Dir["lib/**/*.rb", "[A-Z]*"]
  gem.test_files    = Dir["test/**/*.rb"]
  gem.require_paths = ["lib"]

  gem.add_development_dependency "rake"
  gem.add_development_dependency "pry"
  gem.add_development_dependency "pry-test"
  gem.add_development_dependency "rubocop"
  gem.add_development_dependency "coveralls"
end
