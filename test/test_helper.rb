# frozen_string_literal: true

require "simplecov"

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

require "minitest/autorun"
require_relative "../lib/state_jacket"
