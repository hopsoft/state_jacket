# frozen_string_literal: true

require_relative "test_helper"
require "benchmark"

class PerformanceOptimizationTest < Minitest::Test
  def test_transition_lookup_is_constant_time
    # Test that transition lookup doesn't degrade with more events
    sizes = [10, 50, 100, 500]
    lookup_times = []

    sizes.each do |size|
      transitions = StateJacket::StateTransitionSystem.new
      (0...size).each do |i|
        transitions.add "state_#{i}" => ["state_#{(i + 1) % size}"]
      end

      machine = StateJacket::StateMachine.new(transitions, state: "state_0")
      (0...size).each do |i|
        machine.on "event_#{i}", "state_#{i}" => "state_#{(i + 1) % size}"
      end
      machine.lock

      # Measure lookup time for the last event (worst case in O(n) scenario)
      last_event = "event_#{size - 1}"
      machine.trigger(last_event) # Move to correct state first

      time = Benchmark.realtime do
        1000.times { machine.can_trigger?(last_event) }
      end

      lookup_times << time
    end

    # With O(1) lookup, times should remain relatively constant
    # Allow for some variance due to system noise, but shouldn't scale linearly
    first_time = lookup_times.first
    last_time = lookup_times.last

    # If it was O(n), the last time would be roughly 50x the first time
    # With O(1), it should be close to the same
    ratio = last_time / first_time
    assert ratio < 3.0, "Lookup time ratio #{ratio} suggests O(n) behavior instead of O(1)"
  end

  def test_transition_cache_contains_all_transitions
    transitions = StateJacket::StateTransitionSystem.new
    transitions.add start: [:middle, :end]
    transitions.add middle: [:end]
    transitions.add :end

    machine = StateJacket::StateMachine.new(transitions, state: :start)
    machine.on :advance, start: :middle
    machine.on :skip, start: :end
    machine.on :finish, middle: :end
    machine.lock

    # Verify transition cache contains all expected entries
    transition_cache = machine.instance_variable_get(:@transition_cache)

    assert_equal({"start" => "middle"}, transition_cache[["advance", "start"]])
    assert_equal({"start" => "end"}, transition_cache[["skip", "start"]])
    assert_equal({"middle" => "end"}, transition_cache[["finish", "middle"]])

    # Verify non-existent combinations return nil
    assert_nil transition_cache[["advance", "middle"]]
    assert_nil transition_cache[["finish", "start"]]
  end

  def test_transition_cache_is_frozen_after_lock
    transitions = StateJacket::StateTransitionSystem.new
    transitions.add start: [:end]

    machine = StateJacket::StateMachine.new(transitions, state: :start)
    machine.on :go, start: :end
    machine.lock

    transition_cache = machine.instance_variable_get(:@transition_cache)
    assert transition_cache.frozen?, "Transition cache should be frozen after lock"
  end

  def test_memory_efficiency_of_transition_cache
    # Verify that the transition cache doesn't use excessive memory
    transitions = StateJacket::StateTransitionSystem.new
    100.times do |i|
      transitions.add "state_#{i}" => ["state_#{(i + 1) % 100}"]
    end

    machine = StateJacket::StateMachine.new(transitions, state: "state_0")
    100.times do |i|
      machine.on "event_#{i}", "state_#{i}" => "state_#{(i + 1) % 100}"
    end

    transition_cache = machine.instance_variable_get(:@transition_cache)
    triggers = machine.instance_variable_get(:@triggers)

    # Transition cache should have exactly one entry per transition
    assert_equal 100, transition_cache.size

    # Each trigger should still exist in the original format
    assert_equal 100, triggers.size
    triggers.each_value do |transition_list|
      assert_equal 1, transition_list.size
    end
  end

  def test_complex_state_machine_performance
    # Test with a more complex state machine to ensure optimization works
    transitions = StateJacket::StateTransitionSystem.new
    transitions.add idle: [:connecting, :error]
    transitions.add connecting: [:connected, :failed, :timeout, :error]
    transitions.add connected: [:idle, :transferring]
    transitions.add transferring: [:connected, :completed, :error]
    transitions.add :completed
    transitions.add :failed
    transitions.add :timeout
    transitions.add :error

    machine = StateJacket::StateMachine.new(transitions, state: :idle)
    machine.on :connect, idle: :connecting
    machine.on :success, connecting: :connected
    machine.on :fail, connecting: :failed
    machine.on :timeout_event, connecting: :timeout
    machine.on :transfer, connected: :transferring
    machine.on :complete, transferring: :completed
    machine.on :disconnect, {connected: :idle, transferring: :connected}
    machine.on :error_out, {idle: :error, connecting: :error, transferring: :error}
    machine.lock

    # Measure performance of frequent operations
    time = Benchmark.realtime do
      1000.times do
        machine.can_trigger?(:connect)
        machine.can_trigger?(:success)
        machine.can_trigger?(:transfer)
        machine.can_trigger?(:complete)
        machine.can_trigger?(:disconnect)
        machine.can_trigger?(:error_out)
      end
    end

    # Should complete very quickly with O(1) lookups
    assert time < 0.1, "Complex state machine lookups took #{time}s, may indicate performance regression"
  end

  def test_transition_for_uses_transition_cache
    transitions = StateJacket::StateTransitionSystem.new
    transitions.add start: [:end]

    machine = StateJacket::StateMachine.new(transitions, state: :start)
    machine.on :go, start: :end
    machine.lock

    # Mock the transition cache to verify it's being used
    original_transition_cache = machine.instance_variable_get(:@transition_cache)
    mock_transition_cache = original_transition_cache.dup
    machine.instance_variable_set(:@transition_cache, mock_transition_cache)

    # Add a flag to track access
    access_count = 0
    mock_transition_cache.define_singleton_method(:[]) do |key|
      access_count += 1
      original_transition_cache[key]
    end

    # Call transition_for and verify transition cache was accessed
    result = machine.send(:transition_for, :go)

    assert_equal({"start" => "end"}, result)
    assert access_count > 0, "Transition cache should have been accessed"
  end
end
