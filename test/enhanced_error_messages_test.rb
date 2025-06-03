# frozen_string_literal: true

require_relative "test_helper"

class EnhancedErrorMessagesTest < Minitest::Test
  def setup
    @transitions = StateJacket::StateTransitionSystem.new
  end

  def test_state_transition_system_empty_hash_error
    error = assert_raises(ArgumentError) do
      @transitions.add({})
    end
    assert_equal "transition hash cannot be empty", error.message
  end

  def test_state_transition_system_multiple_transitions_error
    error = assert_raises(ArgumentError) do
      @transitions.add({start: :middle, middle: :end})
    end
    assert_equal "transition hash must contain exactly one key-value pair, got 2: [:start, :middle]", error.message
  end

  def test_state_transition_system_can_transition_empty_hash_error
    @transitions.add start: [:end]
    @transitions.lock

    error = assert_raises(ArgumentError) do
      @transitions.can_transition?({})
    end
    assert_equal "transition hash cannot be empty", error.message
  end

  def test_state_transition_system_can_transition_multiple_pairs_error
    @transitions.add start: [:middle]
    @transitions.add middle: [:end]
    @transitions.lock

    error = assert_raises(ArgumentError) do
      @transitions.can_transition?({start: :middle, middle: :end})
    end
    assert_equal "transition hash must contain exactly one key-value pair, got 2: [:start, :middle]", error.message
  end

  def test_state_machine_illegal_initial_state_error
    @transitions.add start: [:end]

    error = assert_raises(ArgumentError) do
      StateJacket::StateMachine.new(@transitions, state: :invalid)
    end
    assert_equal "illegal state 'invalid'. Available states: end, start", error.message
  end

  def test_state_machine_illegal_initial_state_error_with_no_states
    error = assert_raises(ArgumentError) do
      StateJacket::StateMachine.new(@transitions, state: :invalid)
    end
    assert_equal "illegal state 'invalid'. Available states: none", error.message
  end

  def test_state_machine_duplicate_event_error
    @transitions.add start: [:end]
    machine = StateJacket::StateMachine.new(@transitions, state: :start)
    machine.on :go, start: :end

    error = assert_raises(ArgumentError) do
      machine.on :go, start: :end
    end
    assert_includes error.message, "event 'go' already exists with transitions:"
    assert_includes error.message, "start"
    assert_includes error.message, "end"
  end

  def test_state_machine_illegal_transition_with_undefined_source_state_error
    @transitions.add start: [:end]
    machine = StateJacket::StateMachine.new(@transitions, state: :start)

    error = assert_raises(ArgumentError) do
      machine.on :go, invalid: :end
    end
    assert_equal "illegal transition: source state 'invalid' is not defined in the transition system", error.message
  end

  def test_state_machine_illegal_transition_with_invalid_destination_error
    @transitions.add start: [:middle]
    @transitions.add middle: [:end]
    machine = StateJacket::StateMachine.new(@transitions, state: :start)

    error = assert_raises(ArgumentError) do
      machine.on :go, start: :end
    end
    assert_equal "illegal transition from 'start' to 'end'. Allowed destinations: middle", error.message
  end

  def test_state_machine_illegal_transition_from_terminal_state_error
    @transitions.add start: [:end]
    @transitions.add :end  # terminal state
    machine = StateJacket::StateMachine.new(@transitions, state: :start)

    error = assert_raises(ArgumentError) do
      machine.on :go, end: :start
    end
    assert_equal "illegal transition from 'end' to 'start'. Allowed destinations: none (terminal state)", error.message
  end

  def test_state_machine_trigger_undefined_event_error
    @transitions.add start: [:end]
    machine = StateJacket::StateMachine.new(@transitions, state: :start)
    machine.on :go, start: :end
    machine.lock

    error = assert_raises(ArgumentError) do
      machine.trigger(:invalid)
    end
    assert_equal "event 'invalid' not defined. Available events: go", error.message
  end

  def test_state_machine_trigger_undefined_event_with_no_events_error
    @transitions.add :start
    machine = StateJacket::StateMachine.new(@transitions, state: :start)
    machine.lock

    error = assert_raises(ArgumentError) do
      machine.trigger(:invalid)
    end
    assert_equal "event 'invalid' not defined. Available events: none", error.message
  end

  def test_state_machine_illegal_transition_with_multiple_allowed_destinations
    @transitions.add start: [:middle, :end, :other]
    machine = StateJacket::StateMachine.new(@transitions, state: :start)

    error = assert_raises(ArgumentError) do
      machine.on :go, start: :invalid
    end
    assert_equal "illegal transition from 'start' to 'invalid'. Allowed destinations: middle, end, other", error.message
  end
end
