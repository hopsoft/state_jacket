require "bundler/gem_tasks"
require "rake/testtask"

task default: [:test]

desc "Runs rubocop."
task :rubocop do
  exec "bundle exec rubocop -c .rubocop.yml"
end

Rake::TestTask.new do |t|
  t.libs << "test"
  t.libs << "lib"
  t.test_files = FileList["test/**/*_test.rb"]
end
