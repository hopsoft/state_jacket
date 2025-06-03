# frozen_string_literal: true

require_relative "test_helper"

class ArraySyntaxTest < Minitest::Test
  def setup
    @transitions = StateJacket::StateTransitionSystem.new
    @transitions.add pending: [:processing, :cancelled]
    @transitions.add processing: [:completed, :cancelled]
    @transitions.add completed: [:archived]
    @transitions.add cancelled: [:archived]
    @transitions.add :archived
    @transitions.lock
  end

  def test_array_syntax_with_single_destination
    machine = StateJacket::StateMachine.new(@transitions, state: :pending)
    machine.on :cancel, [:pending, :processing] => :cancelled
    machine.lock

    assert_includes machine.events, "cancel"
    assert machine.can_trigger?(:cancel)

    machine.trigger(:cancel)
    assert_equal "cancelled", machine.state
  end

  def test_array_syntax_from_different_starting_states
    # Test from pending state
    machine1 = StateJacket::StateMachine.new(@transitions, state: :pending)
    machine1.on :cancel, [:pending, :processing] => :cancelled
    machine1.lock

    assert machine1.can_trigger?(:cancel)
    machine1.trigger(:cancel)
    assert_equal "cancelled", machine1.state

    # Test from processing state
    machine2 = StateJacket::StateMachine.new(@transitions, state: :processing)
    machine2.on :cancel, [:pending, :processing] => :cancelled
    machine2.lock

    assert machine2.can_trigger?(:cancel)
    machine2.trigger(:cancel)
    assert_equal "cancelled", machine2.state
  end

  def test_array_syntax_mixed_with_regular_syntax
    machine = StateJacket::StateMachine.new(@transitions, state: :pending)
    machine.on :process, pending: :processing
    machine.on :complete, processing: :completed
    machine.on :cancel, [:pending, :processing] => :cancelled
    machine.on :archive, [:completed, :cancelled] => :archived
    machine.lock

    # Test regular syntax still works
    machine.trigger(:process)
    assert_equal "processing", machine.state

    machine.trigger(:complete)
    assert_equal "completed", machine.state

    # Test array syntax works
    machine.trigger(:archive)
    assert_equal "archived", machine.state
  end

  def test_array_syntax_with_multiple_events
    machine = StateJacket::StateMachine.new(@transitions, state: :pending)
    machine.on :cancel, [:pending, :processing] => :cancelled
    machine.on :archive, [:completed, :cancelled] => :archived
    machine.lock

    expected_to_h = {
      "cancel" => [
        {"pending" => "cancelled"},
        {"processing" => "cancelled"}
      ],
      "archive" => [
        {"completed" => "archived"},
        {"cancelled" => "archived"}
      ]
    }

    assert_equal expected_to_h, machine.to_h
  end

  def test_array_syntax_with_symbols_and_strings
    machine = StateJacket::StateMachine.new(@transitions, state: :pending)
    machine.on :cancel, ["pending", :processing] => "cancelled"
    machine.lock

    assert machine.can_trigger?(:cancel)
    machine.trigger(:cancel)
    assert_equal "cancelled", machine.state
  end

  def test_array_syntax_with_single_element_array
    machine = StateJacket::StateMachine.new(@transitions, state: :pending)
    machine.on :cancel, [:pending] => :cancelled
    machine.lock

    assert machine.can_trigger?(:cancel)
    machine.trigger(:cancel)
    assert_equal "cancelled", machine.state
  end

  def test_array_syntax_validation_failures
    machine = StateJacket::StateMachine.new(@transitions, state: :pending)

    # Should fail if any state in array is invalid
    assert_raises(ArgumentError) do
      machine.on :invalid, [:pending, :nonexistent] => :cancelled
    end

    # Should fail if destination is invalid
    assert_raises(ArgumentError) do
      machine.on :invalid, [:pending, :processing] => :nonexistent
    end
  end

  def test_array_syntax_empty_array_edge_case
    machine = StateJacket::StateMachine.new(@transitions, state: :pending)
    machine.on :noop, [] => :cancelled
    machine.lock

    # Should not create event since no transitions were added
    refute machine.is_event?(:noop)
    assert_nil machine.to_h["noop"]
  end

  def test_array_syntax_preserves_transition_uniqueness
    machine = StateJacket::StateMachine.new(@transitions, state: :pending)
    machine.on :cancel, [:pending, :pending, :processing] => :cancelled
    machine.lock

    # Should not create duplicate transitions
    expected_transitions = [
      {"pending" => "cancelled"},
      {"processing" => "cancelled"}
    ]

    assert_equal expected_transitions, machine.to_h["cancel"]
  end

  def test_array_syntax_triggerable_events_and_reachable_states
    machine = StateJacket::StateMachine.new(@transitions, state: :pending)
    machine.on :process, pending: :processing
    machine.on :cancel, [:pending, :processing] => :cancelled
    machine.lock

    # From pending state
    triggerable = machine.triggerable_events
    assert_includes triggerable, "process"
    assert_includes triggerable, "cancel"

    reachable = machine.reachable_states
    assert_includes reachable, "processing"
    assert_includes reachable, "cancelled"

    # Move to processing and test again
    machine.trigger(:process)
    triggerable = machine.triggerable_events
    refute_includes triggerable, "process"
    assert_includes triggerable, "cancel"

    reachable = machine.reachable_states
    assert_includes reachable, "cancelled"
    refute_includes reachable, "processing"
  end

  def test_array_syntax_with_callback_execution
    machine = StateJacket::StateMachine.new(@transitions, state: :pending)
    machine.on :cancel, [:pending, :processing] => :cancelled
    machine.lock

    callback_executed = false
    from_state = nil
    to_state = nil

    machine.trigger(:cancel) do |from, to|
      callback_executed = true
      from_state = from
      to_state = to
    end

    assert callback_executed
    assert_equal "pending", from_state
    assert_equal "cancelled", to_state
    assert_equal "cancelled", machine.state
  end

  def test_array_syntax_type_conversion
    # Create a separate transition system for this test
    numeric_transitions = StateJacket::StateTransitionSystem.new
    numeric_transitions.add pending: [:cancelled]
    numeric_transitions.add 1 => [2]
    numeric_transitions.add cancelled: [2]
    numeric_transitions.add 2
    numeric_transitions.lock

    machine = StateJacket::StateMachine.new(numeric_transitions, state: :pending)
    machine.on :numeric_transition, [1, "cancelled"] => 2
    machine.lock

    # Both should work due to string conversion
    assert machine.to_h["numeric_transition"].include?({"1" => "2"})
    assert machine.to_h["numeric_transition"].include?({"cancelled" => "2"})
  end
end
