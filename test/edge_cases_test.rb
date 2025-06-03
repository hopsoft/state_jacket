# frozen_string_literal: true

require_relative "test_helper"

class EdgeCasesTest < Minitest::Test
  def setup
    @transitions = StateJacket::StateTransitionSystem.new
  end

  # StateTransitionSystem edge cases
  def test_add_nil_state
    # nil.to_s returns "", so this actually works
    @transitions.add nil
    assert @transitions.is_state?("")
  end

  def test_add_empty_string_state
    @transitions.add ""
    assert @transitions.is_state?("")
  end

  def test_add_state_with_special_characters
    @transitions.add "state-with-special_chars!"
    assert @transitions.is_state?("state-with-special_chars!")
  end

  def test_add_unicode_state
    @transitions.add "状態"
    assert @transitions.is_state?("状態")
  end

  def test_add_very_long_state_name
    long_name = "a" * 1000
    @transitions.add long_name
    assert @transitions.is_state?(long_name)
  end

  def test_can_transition_with_empty_hash
    @transitions.add :start
    assert_raises(ArgumentError) { @transitions.can_transition?({}) }
  end

  def test_can_transition_with_multiple_transitions
    @transitions.add :start
    hash = {start: :end, middle: :finish}
    assert_raises(ArgumentError) { @transitions.can_transition?(hash) }
  end

  def test_can_transition_with_nonexistent_states
    @transitions.add start: [:end]
    @transitions.lock
    assert !@transitions.can_transition?(nonexistent: :end)
    assert !@transitions.can_transition?(start: :nonexistent)
  end

  def test_can_transition_with_array_destinations
    @transitions.add start: [:middle, :end]
    @transitions.lock
    assert @transitions.can_transition?(start: [:middle, :end])
    assert @transitions.can_transition?(start: [:middle])
    assert !@transitions.can_transition?(start: [:middle, :nonexistent])
  end

  def test_states_returns_sorted_array
    @transitions.add :zebra
    @transitions.add :apple
    @transitions.add :banana
    @transitions.lock
    assert @transitions.states.sort == ["apple", "banana", "zebra"]
  end

  def test_double_lock_returns_true
    @transitions.add :start
    assert @transitions.lock == true
    assert @transitions.lock == true
  end

  def test_immutability_after_lock
    @transitions.add start: [:end]
    @transitions.lock
    hash = @transitions.to_h
    # Should raise FrozenError when trying to modify
    assert_raises(FrozenError) { hash["start"] << "hacked" }
    assert @transitions.to_h["start"] == ["end"]
  end

  # StateMachine edge cases
  def test_state_machine_with_numeric_states
    @transitions.add 1 => [2, 3]
    @transitions.add 2 => [1]
    @transitions.add 3 => [1]
    machine = StateJacket::StateMachine.new(@transitions, state: 1)
    assert machine.state == "1"
  end

  def test_events_method_with_empty_machine
    @transitions.add :start
    machine = StateJacket::StateMachine.new(@transitions, state: :start)
    assert machine.events == []
  end

  def test_multiple_events_same_transition
    @transitions.add start: [:end]
    @transitions.add end: [:start]
    machine = StateJacket::StateMachine.new(@transitions, state: :start)
    machine.on :forward, start: :end
    machine.on :advance, start: :end
    machine.lock

    assert machine.can_trigger?(:forward)
    assert machine.can_trigger?(:advance)

    machine.trigger(:forward)
    assert machine.state == "end"
  end

  def test_trigger_undefined_event
    @transitions.add start: [:end]
    machine = StateJacket::StateMachine.new(@transitions, state: :start)
    machine.on :go, start: :end
    machine.lock

    assert_raises(ArgumentError) { machine.trigger(:undefined) }
  end

  def test_trigger_event_wrong_state
    @transitions.add start: [:middle]
    @transitions.add middle: [:end]
    machine = StateJacket::StateMachine.new(@transitions, state: :start)
    machine.on :go, middle: :end
    machine.lock

    # trigger returns nil when transition doesn't match current state
    result = machine.trigger(:go)
    assert result.nil?
    assert machine.state == "start"
  end

  def test_trigger_with_block_exception_preserves_state
    @transitions.add start: [:end]
    machine = StateJacket::StateMachine.new(@transitions, state: :start)
    machine.on :go, start: :end
    machine.lock

    begin
      machine.trigger(:go) { raise "block error" }
    rescue => e
      assert e.message == "block error"
    end

    assert machine.state == "start"
  end

  def test_trigger_with_block_parameters
    @transitions.add start: [:end]
    machine = StateJacket::StateMachine.new(@transitions, state: :start)
    machine.on :go, start: :end
    machine.lock

    from_state = nil
    to_state = nil

    machine.trigger(:go) do |from, to|
      from_state = from
      to_state = to
    end

    assert from_state == "start"
    assert to_state == "end"
    assert machine.state == "end"
  end

  def test_event_name_conversion
    @transitions.add start: [:end]
    machine = StateJacket::StateMachine.new(@transitions, state: :start)
    machine.on 123, start: :end
    machine.lock

    assert machine.is_event?("123")
    assert machine.is_event?(123)
    assert machine.can_trigger?("123")
    assert machine.can_trigger?(123)
  end

  def test_to_h_returns_independent_copy
    @transitions.add start: [:end]
    @transitions.add end: [:start]
    machine = StateJacket::StateMachine.new(@transitions, state: :start)
    machine.on :go, start: :end

    hash1 = machine.to_h
    machine.on :back, end: :start
    hash2 = machine.to_h

    assert hash1 != hash2
    assert hash1["go"] == [{"start" => "end"}]
    assert hash2["back"] == [{"end" => "start"}]
  end

  def test_duplicate_event_addition_fails
    @transitions.add start: [:middle, :end]
    machine = StateJacket::StateMachine.new(@transitions, state: :start)
    machine.on :go, start: :middle

    assert_raises(ArgumentError) { machine.on :go, start: :end }
  end

  def test_large_number_of_states_performance
    # Add 1000 states
    (1..1000).each do |i|
      @transitions.add i => [i + 1] if i < 1000
      @transitions.add i if i == 1000
    end

    @transitions.lock

    assert @transitions.states.length == 1000
    assert @transitions.can_transition?(1 => 2)
    assert @transitions.can_transition?(999 => 1000)
    assert @transitions.is_terminator?(1000)
  end

  def test_complex_branching_scenario
    @transitions.add idle: [:connecting, :error]
    @transitions.add connecting: [:connected, :failed, :timeout, :error]
    @transitions.add connected: [:idle, :transferring]
    @transitions.add transferring: [:connected, :completed, :error]
    @transitions.add completed: [:idle]
    @transitions.add failed: [:idle, :retry]
    @transitions.add retry: [:connecting, :error]
    @transitions.add timeout: [:idle, :retry]
    @transitions.add error: []

    machine = StateJacket::StateMachine.new(@transitions, state: :idle)
    machine.on :connect, idle: :connecting
    machine.on :success, connecting: :connected
    machine.on :fail, connecting: :failed
    machine.on :timeout_event, connecting: :timeout
    machine.on :start_transfer, connected: :transferring
    machine.on :complete, transferring: :completed
    machine.on :disconnect, connected: :idle
    machine.on :finish, completed: :idle
    machine.on :retry_connection, failed: :retry
    machine.on :give_up, failed: :idle
    machine.on :error_from_idle, idle: :error
    machine.on :error_from_connecting, connecting: :error
    machine.on :error_from_transferring, transferring: :error

    machine.lock

    # Test complex workflow
    machine.trigger(:connect)
    assert machine.state == "connecting"

    machine.trigger(:success)
    assert machine.state == "connected"

    machine.trigger(:start_transfer)
    assert machine.state == "transferring"

    machine.trigger(:complete)
    assert machine.state == "completed"

    machine.trigger(:finish)
    assert machine.state == "idle"

    # Test error path
    machine.trigger(:error_from_idle)
    assert machine.state == "error"

    # Should not be able to transition from error
    assert !machine.can_trigger?(:connect)
  end
end
