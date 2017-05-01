require "bundler/gem_tasks"

task default: [:test]

desc "Runs rubocop."
task :rubocop do
  exec "bundle exec rubocop -c .rubocop.yml"
end

desc "Runs the test suite."
task :test do
  exec "bundle exec pry-test --disable-pry"
end
