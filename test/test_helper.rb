# frozen_string_literal: true

require "simplecov"
require "amazing_print"

# Prevent all plugin auto-discovery and load minitest-reporters manually
ENV["MT_NO_PLUGINS"] = "1"

require "minitest"
require "minitest/reporters"
require "minitest/minitest_reporter_plugin"

# Configure reporters before autorun
Minitest::Reporters.use! [
  Minitest::Reporters::DefaultReporter.new(color: true, fail_fast: true, location: true),
  Minitest::Reporters::MeanTimeReporter.new(show_count: 3, show_progress: false, sort_column: :avg, previous_runs_filename: "tmp/minitest-report")
]

# Manually register the reporter plugin since we disabled auto-discovery
Minitest.extensions << "minitest_reporter"

require "minitest/autorun"
require "pry-byebug"

AmazingPrint.pry!
FileUtils.mkdir_p "tmp"

# Configure SimpleCov with Coveralls integration for CI environments
SimpleCov.start do
  command_name "Unit Tests"
  add_filter "/test/"

  # Only use Coveralls in CI environments
  if ENV["CI"] || ENV["GITHUB_ACTIONS"] || ENV["COVERALLS_REPO_TOKEN"]
    require "coveralls"
    formatter SimpleCov::Formatter::MultiFormatter.new([
      SimpleCov::Formatter::HTMLFormatter,
      Coveralls::SimpleCov::Formatter
    ])
  end
end

class Test < Minitest::Test
  make_my_diffs_pretty!
end

require_relative "../lib/state_jacket"
