require "bundler/gem_tasks"

task :default => [:test]

desc "Runs the test suite."
task :test do
  exec "bundle exec pry-test --disable-pry"
end

