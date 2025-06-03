# frozen_string_literal: true

require_relative "test_helper"

class StateMachineTest < Minitest::Test
  def setup
    @transitions = StateJacket::StateTransitionSystem.new
  end

  def test_new_raises_with_invalid_state
    @transitions.add opened: [:closed, :errored]
    @transitions.add closed: [:opened, :errored]
    begin
      StateJacket::StateMachine.new(@transitions, state: :foo)
    rescue ArgumentError => e
    end
    assert e
  end

  def test_new_assigns_state
    @transitions.add opened: [:closed, :errored]
    @transitions.add closed: [:opened, :errored]
    machine = StateJacket::StateMachine.new(@transitions, state: :opened)
    assert machine.state == "opened"
  end

  def test_new_locks_the_jacket
    @transitions.add opened: [:closed, :errored]
    @transitions.add closed: [:opened, :errored]
    StateJacket::StateMachine.new(@transitions, state: :closed)
    assert @transitions.locked?
  end

  def test_creating_an_event_that_has_an_illegal_transition_fails
    @transitions.add opened: [:closed, :errored]
    @transitions.add closed: [:opened, :errored]
    machine = StateJacket::StateMachine.new(@transitions, state: :closed)
    begin
      machine.on :reopen, errored: :open
    rescue => e
    end
    assert e
  end

  def test_to_h
    @transitions.add opened: [:closed, :errored]
    @transitions.add closed: [:opened, :errored]
    machine = StateJacket::StateMachine.new(@transitions, state: :closed)
    machine.on :open, closed: :opened
    machine.on :close, opened: :closed
    assert machine.to_h == {"open" => [{"closed" => "opened"}], "close" => [{"opened" => "closed"}]}
  end

  def test_events
    @transitions.add opened: [:closed, :errored]
    @transitions.add closed: [:opened, :errored]
    machine = StateJacket::StateMachine.new(@transitions, state: :closed)
    machine.on :open, closed: :opened
    machine.on :close, opened: :closed
    assert machine.events.sort == ["close", "open"]
  end

  def test_states
    @transitions.add opened: [:closed, :errored]
    @transitions.add closed: [:opened, :errored]
    @transitions.add :errored
    machine = StateJacket::StateMachine.new(@transitions, state: :closed)
    assert machine.states.sort == ["closed", "errored", "opened"]
  end

  def test_lock_prevents_future_mutations
    @transitions.add opened: [:closed, :errored]
    @transitions.add closed: [:opened, :errored]
    machine = StateJacket::StateMachine.new(@transitions, state: :closed)
    machine.on :open, closed: :opened
    machine.on :close, opened: :closed
    assert machine.lock
    assert machine.locked?
    begin
      machine.on :error, closed: :opened
    rescue => e
    end
    assert e
  end

  def test_cant_trigger_events_unless_locked
    @transitions.add opened: [:closed]
    @transitions.add closed: [:opened]
    machine = StateJacket::StateMachine.new(@transitions, state: :closed)
    machine.on :open, closed: :opened
    machine.on :close, opened: :closed
    begin
      machine.trigger :open
    rescue => e
    end
    assert e
  end

  def test_trigger_event_sets_matching_state
    @transitions.add opened: [:closed]
    @transitions.add closed: [:opened]
    machine = StateJacket::StateMachine.new(@transitions, state: :closed)
    machine.on :open, closed: :opened
    machine.on :close, opened: :closed
    machine.lock
    machine.trigger :open
    assert machine.state == "opened"
    machine.trigger :close
    assert machine.state == "closed"
  end

  def test_trigger_noop
    @transitions.add opened: [:closed]
    @transitions.add closed: [:opened]
    machine = StateJacket::StateMachine.new(@transitions, state: :closed)
    machine.on :open, closed: :opened
    machine.on :close, opened: :closed
    machine.lock
    result1 = machine.trigger(:open)
    assert result1.success?
    assert_equal "opened", result1.to_state
    result2 = machine.trigger(:open)
    assert result2.failed?
  end

  def test_trigger_event_sets_matching_state_with_block
    @transitions.add opened: [:closed]
    @transitions.add closed: [:opened]
    machine = StateJacket::StateMachine.new(@transitions, state: :closed)
    machine.on :open, closed: :opened
    machine.on :close, opened: :closed
    machine.lock
    machine.trigger(:open) { |from, to| "consumer logic goes here..." }
    assert machine.state == "opened"
    machine.trigger(:close) { |from, to| "consumer logic goes here..." }
    assert machine.state == "closed"
  end

  def test_trigger_event_does_not_set_state_if_error_in_block
    @transitions.add opened: [:closed]
    @transitions.add closed: [:opened]
    machine = StateJacket::StateMachine.new(@transitions, state: :closed)
    machine.on :open, closed: :opened
    machine.on :close, opened: :closed
    machine.lock
    begin
      machine.trigger(:open) { |from, to| raise }
    rescue
      nil
    end
    assert machine.state == "closed"
  end

  def test_trigger_event_passes_from_to_states_to_block
    @transitions.add opened: [:closed]
    @transitions.add closed: [:opened]
    machine = StateJacket::StateMachine.new(@transitions, state: :closed)
    machine.on :open, closed: :opened
    machine.on :close, opened: :closed
    machine.lock
    states = {from: nil, to: nil}
    machine.trigger :open do |from, to|
      states[:from] = from
      states[:to] = to
    end
    assert states == {from: "closed", to: "opened"}
  end

  def test_can_trigger_false_unless_locked
    @transitions.add opened: [:closed, :errored]
    @transitions.add closed: [:opened, :errored]
    machine = StateJacket::StateMachine.new(@transitions, state: :closed)
    machine.on :open, closed: :opened
    machine.on :close, opened: :closed
    assert !machine.can_trigger?(:open)
  end

  def test_can_trigger
    @transitions.add opened: [:closed, :errored]
    @transitions.add closed: [:opened, :errored]
    machine = StateJacket::StateMachine.new(@transitions, state: :closed)
    machine.on :open, closed: :opened
    machine.on :close, opened: :closed
    machine.lock
    assert machine.can_trigger?(:open)
  end

  def test_can_trigger_false
    @transitions.add opened: [:closed, :errored]
    @transitions.add closed: [:opened, :errored]
    machine = StateJacket::StateMachine.new(@transitions, state: :closed)
    machine.on :open, closed: :opened
    machine.on :close, opened: :closed
    machine.lock
    assert !machine.can_trigger?(:close)
  end

  def test_triggerable_events
    @transitions.add opened: [:closed, :errored]
    @transitions.add closed: [:opened, :errored]
    @transitions.add :errored
    machine = StateJacket::StateMachine.new(@transitions, state: :closed)
    machine.on :open, closed: :opened
    machine.on :close, opened: :closed
    machine.on :error, {closed: :errored, opened: :errored}
    machine.lock

    available = machine.triggerable_events
    assert_includes available, "open"
    assert_includes available, "error"
    refute_includes available, "close"
  end

  def test_reachable_states
    @transitions.add opened: [:closed, :errored]
    @transitions.add closed: [:opened, :errored]
    @transitions.add :errored
    machine = StateJacket::StateMachine.new(@transitions, state: :closed)
    machine.on :open, closed: :opened
    machine.on :close, opened: :closed
    machine.on :error, {closed: :errored, opened: :errored}
    machine.lock

    available = machine.reachable_states
    assert_includes available, "opened"
    assert_includes available, "errored"
    refute_includes available, "closed"
  end

  def test_terminal
    @transitions.add opened: [:closed, :errored]
    @transitions.add closed: [:opened, :errored]
    @transitions.add :errored
    machine = StateJacket::StateMachine.new(@transitions, state: :closed)
    machine.on :open, closed: :opened
    machine.on :error, {closed: :errored, opened: :errored}
    machine.lock

    refute machine.terminal?
    machine.trigger(:error)
    assert machine.terminal?
  end

  def test_state_symbol
    @transitions.add opened: [:closed, :errored]
    @transitions.add closed: [:opened, :errored]
    machine = StateJacket::StateMachine.new(@transitions, state: :closed)

    assert_equal :closed, machine.state_symbol
    assert_instance_of Symbol, machine.state_symbol
  end
end
