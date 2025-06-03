# frozen_string_literal: true

require_relative "test_helper"
require "benchmark"

class PerformanceTest < Minitest::Test
  def test_large_transition_system_creation_performance
    benchmark_result = Benchmark.measure do
      transitions = StateJacket::StateTransitionSystem.new

      # Create 1000 states with transitions
      1000.times do |i|
        next_states = [(i + 1) % 1000, (i + 2) % 1000, (i + 3) % 1000]
        transitions.add i => next_states
      end

      transitions.lock
    end

    # Should complete in reasonable time (less than 1 second)
    assert benchmark_result.real < 1.0, "Large transition system creation took #{benchmark_result.real}s"
  end

  def test_state_machine_with_many_events_performance
    transitions = StateJacket::StateTransitionSystem.new

    # Create states
    100.times do |i|
      transitions.add "state_#{i}": [:"state_#{(i + 1) % 100}"]
    end

    machine = StateJacket::StateMachine.new(transitions, state: :state_0)

    benchmark_result = Benchmark.measure do
      # Add 100 events
      100.times do |i|
        machine.on :"event_#{i}", "state_#{i}": :"state_#{(i + 1) % 100}"
      end
      machine.lock
    end

    assert benchmark_result.real < 0.5, "Adding 100 events took #{benchmark_result.real}s"
    assert machine.events.length == 100
  end

  def test_rapid_state_transitions_performance
    transitions = StateJacket::StateTransitionSystem.new
    transitions.add state_a: [:state_b]
    transitions.add state_b: [:state_a]

    machine = StateJacket::StateMachine.new(transitions, state: :state_a)
    machine.on :toggle, {state_a: :state_b, state_b: :state_a}
    machine.lock

    benchmark_result = Benchmark.measure do
      # Perform 10,000 state transitions
      10_000.times do
        machine.trigger(:toggle)
      end
    end

    assert benchmark_result.real < 1.0, "10,000 transitions took #{benchmark_result.real}s"
  end

  def test_deep_state_hierarchy_performance
    transitions = StateJacket::StateTransitionSystem.new

    # Create a chain of 500 states
    500.times do |i|
      if i == 499
        transitions.add "level_#{i}": []
      else
        transitions.add "level_#{i}": [:"level_#{i + 1}"]
      end
    end

    machine = StateJacket::StateMachine.new(transitions, state: :level_0)

    # Add events for each transition
    499.times do |i|
      machine.on :"advance_#{i}", "level_#{i}": :"level_#{i + 1}"
    end

    machine.lock

    benchmark_result = Benchmark.measure do
      # Navigate through the entire hierarchy
      499.times do |i|
        machine.trigger(:"advance_#{i}")
      end
    end

    assert benchmark_result.real < 0.5, "Deep hierarchy navigation took #{benchmark_result.real}s"
    assert machine.state == "level_499"
  end

  def test_memory_usage_with_large_transition_system
    # Test that memory usage doesn't grow excessively
    gc_start = GC.stat(:total_allocated_objects)

    transitions = StateJacket::StateTransitionSystem.new

    # Create 500 states with multiple transitions each
    500.times do |i|
      destinations = []
      5.times do |j|
        destinations << "dest_#{i}_#{j}"
      end
      transitions.add "source_#{i}" => destinations
    end

    machine = StateJacket::StateMachine.new(transitions, state: "source_0")

    # Add events
    500.times do |i|
      5.times do |j|
        machine.on "event_#{i}_#{j}", "source_#{i}" => "dest_#{i}_#{j}"
      end
    end

    machine.lock

    gc_end = GC.stat(:total_allocated_objects)
    objects_created = gc_end - gc_start

    # Should not create an excessive number of objects (threshold: 100,000)
    assert objects_created < 100_000, "Created #{objects_created} objects, which seems excessive"
  end

  def test_concurrent_read_operations_safety
    # Test that read operations are safe when called concurrently
    transitions = StateJacket::StateTransitionSystem.new
    transitions.add idle: [:working, :error]
    transitions.add working: [:idle, :completed]
    transitions.add completed: [:idle]
    transitions.add error: [:idle]

    machine = StateJacket::StateMachine.new(transitions, state: :idle)
    machine.on :start, idle: :working
    machine.on :finish, working: :completed
    machine.on :reset, {completed: :idle, error: :idle}
    machine.lock

    # Simulate concurrent reads
    threads = []
    results = []

    10.times do
      threads << Thread.new do
        100.times do
          results << machine.state
          results << machine.events
          results << machine.to_h.keys
          results << machine.can_trigger?(:start)
        end
      end
    end

    threads.each(&:join)

    # Verify no errors occurred and results are consistent
    assert results.length == 4000 # 10 threads * 100 iterations * 4 operations
    assert results.all? { |r| !r.nil? }
  end

  def test_string_conversion_performance
    transitions = StateJacket::StateTransitionSystem.new

    benchmark_result = Benchmark.measure do
      # Test various input types and their string conversion
      1000.times do |i|
        transitions.add i => [i + 1000]
        transitions.add "string_#{i}" => ["string_#{i + 1000}"]
        transitions.add "symbol_#{i}": [:"symbol_#{i + 1000}"]
      end
      transitions.lock
    end

    assert benchmark_result.real < 1.0, "String conversion performance took #{benchmark_result.real}s"
    assert transitions.states.length == 6000
  end

  def test_event_lookup_performance
    transitions = StateJacket::StateTransitionSystem.new
    transitions.add start: (1..1000).map { |i| "state_#{i}" }

    machine = StateJacket::StateMachine.new(transitions, state: :start)

    # Add 1000 events
    1000.times do |i|
      machine.on "event_#{i}", start: "state_#{i + 1}"
    end

    machine.lock

    benchmark_result = Benchmark.measure do
      # Test event existence checks
      2000.times do |i|
        machine.event?("event_#{i % 1000}")
        machine.can_trigger?("event_#{i % 1000}")
      end
    end

    assert benchmark_result.real < 0.5, "Event lookup performance took #{benchmark_result.real}s"
  end

  def test_frozen_object_access_performance
    transitions = StateJacket::StateTransitionSystem.new

    100.times do |i|
      transitions.add "state_#{i}" => ["state_#{(i + 1) % 100}"]
    end

    machine = StateJacket::StateMachine.new(transitions, state: "state_0")

    100.times do |i|
      machine.on "event_#{i}", "state_#{i}" => "state_#{(i + 1) % 100}"
    end

    machine.lock

    benchmark_result = Benchmark.measure do
      # Access frozen data structures repeatedly
      1000.times do
        machine.to_h
        machine.events
        transitions.to_h
        transitions.states
      end
    end

    assert benchmark_result.real < 0.5, "Frozen object access took #{benchmark_result.real}s"
  end
end
