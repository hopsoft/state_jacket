# -*- encoding: utf-8 -*-
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'state_jacket/version'

Gem::Specification.new do |gem|
  gem.name          = "state_jacket"
  gem.version       = StateJacket::VERSION
  gem.authors       = ["Nathan Hopkins"]
  gem.email         = ["natehop@gmail.com"]
  gem.summary       = "Intuitively define state machine like states and transitions."
  gem.homepage      = ""

  gem.files         = `git ls-files`.split($/)
  gem.executables   = gem.files.grep(%r{^bin/}).map{ |f| File.basename(f) }
  gem.test_files    = gem.files.grep(%r{^(test|spec|features)/})
  gem.require_paths = ["lib"]

  gem.add_development_dependency "micro_test"
  gem.add_development_dependency "pry"
  gem.add_development_dependency "pry-stack_explorer"
end
