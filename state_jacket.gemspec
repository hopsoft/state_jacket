# -*- encoding: utf-8 -*-
require File.join(File.dirname(__FILE__), "lib", "state_jacket", "version")

Gem::Specification.new do |gem|
  gem.name          = "state_jacket"
  gem.license       = "MIT"
  gem.version       = StateJacket::VERSION
  gem.authors       = ["Nathan Hopkins"]
  gem.email         = ["natehop@gmail.com"]
  gem.summary       = "Intuitively define state machine like states and transitions."
  gem.description   = "Intuitively define state machine like states and transitions."
  gem.homepage      = "https://github.com/hopsoft/state_jacket"

  gem.files         = Dir["lib/**/*.rb", "[A-Z]*"]
  gem.test_files    = Dir["test/**/*.rb"]
  gem.require_paths = ["lib"]

  gem.add_development_dependency "micro_test"
  gem.add_development_dependency "pry"
  gem.add_development_dependency "pry-stack_explorer"
end
