require File.join(File.dirname(__FILE__), "lib", "state_jacket", "version")

Gem::Specification.new do |gem|
  gem.name = "state_jacket"
  gem.license = "MIT"
  gem.version = StateJacket::VERSION
  gem.authors = ["Nathan Hopkins"]
  gem.email = ["natehop@gmail.com"]
  gem.summary = "A simple & intuitive state machine"
  gem.homepage = "https://github.com/hopsoft/state_jacket"

  gem.files = Dir["lib/**/*.rb", "sig/**/*.rbs", "README.md", "LICENSE.txt"]
  gem.require_paths = ["lib"]

  gem.add_development_dependency "amazing_print"
  gem.add_development_dependency "benchmark"
  gem.add_development_dependency "coveralls_reborn"
  gem.add_development_dependency "irb"
  gem.add_development_dependency "minitest"
  gem.add_development_dependency "minitest-reporters"
  gem.add_development_dependency "pry-byebug"
  gem.add_development_dependency "rake"
  gem.add_development_dependency "rbs-inline"
  gem.add_development_dependency "reline"
  gem.add_development_dependency "standard"
end
