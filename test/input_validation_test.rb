# frozen_string_literal: true

require_relative "test_helper"

class InputValidationTest < Minitest::Test
  def setup
    @transitions = StateJacket::StateTransitionSystem.new
  end

  # StateTransitionSystem validation tests
  def test_can_transition_validates_nil_argument
    @transitions.add start: [:end]
    @transitions.lock

    error = assert_raises(ArgumentError) do
      @transitions.can_transition?(nil)
    end
    assert_equal "transition argument cannot be nil", error.message
  end

  def test_can_transition_validates_empty_hash
    @transitions.add start: [:end]
    @transitions.lock

    error = assert_raises(ArgumentError) do
      @transitions.can_transition?({})
    end
    assert_equal "transition hash cannot be empty", error.message
  end

  def test_can_transition_validates_multiple_pairs
    @transitions.add start: [:middle]
    @transitions.add middle: [:end]
    @transitions.lock

    error = assert_raises(ArgumentError) do
      @transitions.can_transition?({start: :middle, middle: :end})
    end
    assert_equal "transition hash must contain exactly one key-value pair, got 2: [:start, :middle]", error.message
  end

  def test_can_transition_returns_false_for_undefined_source_state
    @transitions.add start: [:end]
    @transitions.lock

    result = @transitions.can_transition?(undefined: :end)
    assert_equal false, result
  end

  def test_can_transition_returns_false_for_invalid_destination
    @transitions.add start: [:middle]
    @transitions.add middle: [:end]
    @transitions.lock

    result = @transitions.can_transition?(start: :end)
    assert_equal false, result
  end

  def test_can_transition_returns_true_for_valid_transition
    @transitions.add start: [:end]
    @transitions.lock

    result = @transitions.can_transition?(start: :end)
    assert_equal true, result
  end

  def test_add_validates_empty_hash
    error = assert_raises(ArgumentError) do
      @transitions.add({})
    end
    assert_equal "transition hash cannot be empty", error.message
  end

  def test_add_validates_multiple_pairs_in_hash
    error = assert_raises(ArgumentError) do
      @transitions.add({start: :middle, middle: :end})
    end
    assert_equal "transition hash must contain exactly one key-value pair, got 2: [:start, :middle]", error.message
  end

  # StateMachine validation tests
  def test_initialize_validates_nil_transition_system
    error = assert_raises(ArgumentError) do
      StateJacket::StateMachine.new(nil, state: :start)
    end
    assert_equal "transition_system cannot be nil", error.message
  end

  def test_initialize_validates_undefined_state
    @transitions.add start: [:end]

    error = assert_raises(ArgumentError) do
      StateJacket::StateMachine.new(@transitions, state: :undefined)
    end
    assert_equal "illegal state 'undefined'. Available states: end, start", error.message
  end

  def test_on_validates_nil_transitions_hash
    @transitions.add start: [:end]
    machine = StateJacket::StateMachine.new(@transitions, state: :start)

    error = assert_raises(ArgumentError) do
      machine.on :go, nil
    end
    assert_equal "transitions cannot be nil", error.message
  end

  def test_on_validates_duplicate_event
    @transitions.add start: [:end]
    machine = StateJacket::StateMachine.new(@transitions, state: :start)
    machine.on :go, start: :end

    error = assert_raises(ArgumentError) do
      machine.on :go, start: :end
    end
    assert_includes error.message, "event 'go' already exists"
  end

  def test_on_validates_illegal_transition
    @transitions.add start: [:middle]
    machine = StateJacket::StateMachine.new(@transitions, state: :start)

    error = assert_raises(ArgumentError) do
      machine.on :go, start: :end
    end
    assert_equal "illegal transition from 'start' to 'end'. Allowed destinations: middle", error.message
  end

  def test_on_validates_undefined_source_state
    @transitions.add start: [:end]
    machine = StateJacket::StateMachine.new(@transitions, state: :start)

    error = assert_raises(ArgumentError) do
      machine.on :go, undefined: :end
    end
    assert_equal "illegal transition: from state 'undefined' is not defined in the transition system", error.message
  end

  def test_trigger_validates_undefined_event
    @transitions.add start: [:end]
    machine = StateJacket::StateMachine.new(@transitions, state: :start)
    machine.on :go, start: :end
    machine.lock

    error = assert_raises(ArgumentError) do
      machine.trigger(:undefined)
    end
    assert_equal "event 'undefined' not defined. Available events: go", error.message
  end

  def test_trigger_validates_machine_not_locked
    @transitions.add start: [:end]
    machine = StateJacket::StateMachine.new(@transitions, state: :start)
    machine.on :go, start: :end

    error = assert_raises(RuntimeError) do
      machine.trigger(:go)
    end
    assert_equal "must be locked before triggering events", error.message
  end

  # Edge cases that should work (nil converted to string)
  def test_nil_state_converts_to_empty_string
    @transitions.add nil
    assert @transitions.is_state?("")
    assert @transitions.is_state?(nil)
  end

  def test_nil_in_transition_hash_converts_to_string
    @transitions.add nil => [nil]
    assert @transitions.can_transition?(nil => nil)
    assert @transitions.can_transition?("" => "")
  end

  def test_machine_with_nil_state_works
    @transitions.add nil => [:start]
    @transitions.add :start
    machine = StateJacket::StateMachine.new(@transitions, state: nil)
    assert_equal "", machine.state
  end

  def test_machine_with_nil_event_works
    @transitions.add start: [:end]
    machine = StateJacket::StateMachine.new(@transitions, state: :start)
    machine.on nil, start: :end
    machine.lock

    assert machine.is_event?("")
    assert machine.is_event?(nil)
  end

  # Complex validation scenarios
  def test_array_destination_validation
    @transitions.add start: [:middle, :end]
    @transitions.add :middle
    @transitions.add :end

    # Valid array transitions
    assert @transitions.can_transition?(start: [:middle, :end])
    assert @transitions.can_transition?(start: [:middle])

    # Invalid array transitions
    assert_equal false, @transitions.can_transition?(start: [:middle, :invalid])
    assert_equal false, @transitions.can_transition?(start: [:invalid])
  end

  def test_validation_with_complex_state_names
    @transitions.add "state-with-dashes" => ["state_with_underscores"]
    @transitions.add "state_with_underscores" => ["state with spaces"]
    @transitions.add "state with spaces"

    assert @transitions.can_transition?("state-with-dashes" => "state_with_underscores")
    assert @transitions.can_transition?("state_with_underscores" => "state with spaces")
    assert_equal false, @transitions.can_transition?("state with spaces" => "nonexistent")
  end

  def test_validation_preserves_original_behavior
    # Ensure enhanced validation doesn't break existing functionality
    @transitions.add idle: [:connecting, :error]
    @transitions.add connecting: [:connected, :failed, :timeout, :error]
    @transitions.add connected: [:idle, :transferring]
    @transitions.add transferring: [:connected, :completed, :error]
    @transitions.add :completed
    @transitions.add :failed
    @transitions.add :timeout
    @transitions.add :error

    machine = StateJacket::StateMachine.new(@transitions, state: :idle)
    machine.on :connect, idle: :connecting
    machine.on :success, connecting: :connected
    machine.on :transfer, connected: :transferring
    machine.on :complete, transferring: :completed
    machine.on :disconnect, {connected: :idle, transferring: :connected}
    machine.on :error_out, {idle: :error, connecting: :error, transferring: :error}
    machine.lock

    # Test normal workflow
    machine.trigger(:connect)
    assert_equal "connecting", machine.state

    machine.trigger(:success)
    assert_equal "connected", machine.state

    machine.trigger(:transfer)
    assert_equal "transferring", machine.state

    machine.trigger(:complete)
    assert_equal "completed", machine.state
  end
end
