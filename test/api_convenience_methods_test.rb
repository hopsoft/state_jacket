# frozen_string_literal: true

require_relative "test_helper"

class ApiConvenienceMethodsTest < Minitest::Test
  def setup
    @transitions = StateJacket::StateTransitionSystem.new
  end

  # triggerable_events tests
  def test_triggerable_events_returns_empty_when_not_locked
    @transitions.add start: [:end]
    machine = StateJacket::StateMachine.new(@transitions, state: :start)
    machine.on :go, start: :end

    assert_equal [], machine.triggerable_events
  end

  def test_triggerable_events_returns_triggerable_events
    @transitions.add start: [:middle, :end]
    @transitions.add middle: [:end]
    @transitions.add :end

    machine = StateJacket::StateMachine.new(@transitions, state: :start)
    machine.on :advance, start: :middle
    machine.on :skip, start: :end
    machine.on :finish, middle: :end
    machine.lock

    available = machine.triggerable_events
    assert_equal 2, available.length
    assert_includes available, "advance"
    assert_includes available, "skip"
    refute_includes available, "finish"
  end

  def test_triggerable_events_changes_with_state
    @transitions.add start: [:middle, :end]
    @transitions.add middle: [:end]
    @transitions.add :end

    machine = StateJacket::StateMachine.new(@transitions, state: :start)
    machine.on :advance, start: :middle
    machine.on :skip, start: :end
    machine.on :finish, middle: :end
    machine.lock

    # From start state
    available = machine.triggerable_events
    assert_includes available, "advance"
    assert_includes available, "skip"
    refute_includes available, "finish"

    # Move to middle state
    machine.trigger(:advance)
    available = machine.triggerable_events
    refute_includes available, "advance"
    refute_includes available, "skip"
    assert_includes available, "finish"
  end

  def test_triggerable_events_empty_for_terminal_state
    @transitions.add start: [:end]
    @transitions.add :end

    machine = StateJacket::StateMachine.new(@transitions, state: :start)
    machine.on :finish, start: :end
    machine.lock

    machine.trigger(:finish)
    assert_equal [], machine.triggerable_events
  end

  # reachable_states tests
  def test_reachable_states_returns_destination_states
    @transitions.add start: [:middle, :end]
    @transitions.add middle: [:end]
    @transitions.add :end

    machine = StateJacket::StateMachine.new(@transitions, state: :start)
    machine.on :advance, start: :middle
    machine.on :skip, start: :end
    machine.on :finish, middle: :end
    machine.lock

    available = machine.reachable_states
    assert_equal 2, available.length
    assert_includes available, "middle"
    assert_includes available, "end"
  end

  def test_reachable_states_changes_with_state
    @transitions.add start: [:middle, :end]
    @transitions.add middle: [:end]
    @transitions.add :end

    machine = StateJacket::StateMachine.new(@transitions, state: :start)
    machine.on :advance, start: :middle
    machine.on :skip, start: :end
    machine.on :finish, middle: :end
    machine.lock

    # From start state
    available = machine.reachable_states
    assert_includes available, "middle"
    assert_includes available, "end"

    # Move to middle state
    machine.trigger(:advance)
    available = machine.reachable_states
    assert_equal ["end"], available
  end

  def test_reachable_states_empty_for_terminal_state
    @transitions.add start: [:end]
    @transitions.add :end

    machine = StateJacket::StateMachine.new(@transitions, state: :start)
    machine.on :finish, start: :end
    machine.lock

    machine.trigger(:finish)
    assert_equal [], machine.reachable_states
  end

  def test_reachable_states_removes_duplicates
    @transitions.add start: [:end]
    @transitions.add :end

    machine = StateJacket::StateMachine.new(@transitions, state: :start)
    machine.on :finish1, start: :end
    machine.on :finish2, start: :end
    machine.lock

    available = machine.reachable_states
    assert_equal ["end"], available
  end

  # terminal? tests
  def test_terminal_false_for_non_terminal_state
    @transitions.add start: [:end]
    @transitions.add :end

    machine = StateJacket::StateMachine.new(@transitions, state: :start)
    refute machine.terminal?
  end

  def test_terminal_true_for_terminal_state
    @transitions.add start: [:end]
    @transitions.add :end

    machine = StateJacket::StateMachine.new(@transitions, state: :start)
    machine.on :finish, start: :end
    machine.lock

    machine.trigger(:finish)
    assert machine.terminal?
  end

  def test_terminal_with_complex_state_machine
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
    machine.on :complete, transferring: :completed
    machine.lock

    # Non-terminal states
    refute machine.terminal? # idle
    machine.trigger(:connect)
    refute machine.terminal? # connecting
    machine.trigger(:success)
    refute machine.terminal? # connected

    # Transition to terminal state
    machine = StateJacket::StateMachine.new(@transitions, state: :transferring)
    machine.on :complete, transferring: :completed
    machine.lock
    machine.trigger(:complete)
    assert machine.terminal? # completed
  end

  # state_symbol tests
  def test_state_symbol_returns_symbol
    @transitions.add :start

    machine = StateJacket::StateMachine.new(@transitions, state: :start)
    assert_equal :start, machine.state_symbol
    assert_instance_of Symbol, machine.state_symbol
  end

  def test_state_symbol_converts_string_state
    @transitions.add "start" => ["end"]
    @transitions.add "end"

    machine = StateJacket::StateMachine.new(@transitions, state: "start")
    assert_equal :start, machine.state_symbol

    machine.on :go, "start" => "end"
    machine.lock
    machine.trigger(:go)
    assert_equal :end, machine.state_symbol
  end

  def test_state_symbol_with_complex_state_names
    @transitions.add "state-with-dashes" => ["state_with_underscores"]
    @transitions.add "state_with_underscores"

    machine = StateJacket::StateMachine.new(@transitions, state: "state-with-dashes")
    assert_equal :"state-with-dashes", machine.state_symbol

    machine.on :advance, "state-with-dashes" => "state_with_underscores"
    machine.lock
    machine.trigger(:advance)
    assert_equal :state_with_underscores, machine.state_symbol
  end

  def test_state_symbol_with_numeric_conversion
    @transitions.add 1 => [2]
    @transitions.add 2

    machine = StateJacket::StateMachine.new(@transitions, state: 1)
    assert_equal :"1", machine.state_symbol

    machine.on :next, 1 => 2
    machine.lock
    machine.trigger(:next)
    assert_equal :"2", machine.state_symbol
  end

  # Integration tests combining multiple convenience methods
  def test_convenience_methods_work_together
    @transitions.add draft: [:review, :archived]
    @transitions.add review: [:published, :draft]
    @transitions.add published: [:archived, :draft]
    @transitions.add :archived

    machine = StateJacket::StateMachine.new(@transitions, state: :draft)
    machine.on :submit, draft: :review
    machine.on :publish, review: :published
    machine.on :archive, {draft: :archived, published: :archived}
    machine.on :revise, {review: :draft, published: :draft}
    machine.lock

    # Draft state
    assert_equal :draft, machine.state_symbol
    refute machine.terminal?
    assert_includes machine.triggerable_events, "submit"
    assert_includes machine.triggerable_events, "archive"
    assert_includes machine.reachable_states, "review"
    assert_includes machine.reachable_states, "archived"

    # Review state
    machine.trigger(:submit)
    assert_equal :review, machine.state_symbol
    refute machine.terminal?
    assert_includes machine.triggerable_events, "publish"
    assert_includes machine.triggerable_events, "revise"
    assert_includes machine.reachable_states, "published"
    assert_includes machine.reachable_states, "draft"

    # Archived state (terminal)
    machine.trigger(:revise)
    machine.trigger(:archive)
    assert_equal :archived, machine.state_symbol
    assert machine.terminal?
    assert_equal [], machine.triggerable_events
    assert_equal [], machine.reachable_states
  end

  def test_convenience_methods_with_no_events_defined
    @transitions.add :start

    machine = StateJacket::StateMachine.new(@transitions, state: :start)
    machine.lock

    assert_equal [], machine.triggerable_events
    assert_equal [], machine.reachable_states
    assert machine.terminal?
    assert_equal :start, machine.state_symbol
  end

  def test_convenience_methods_with_events_from_other_states
    @transitions.add start: [:middle]
    @transitions.add middle: [:end]
    @transitions.add :end

    machine = StateJacket::StateMachine.new(@transitions, state: :start)
    machine.on :advance_to_end, middle: :end # Event only valid from middle
    machine.lock

    # From start state, can't trigger event meant for middle state
    assert_equal [], machine.triggerable_events
    assert_equal [], machine.reachable_states
    refute machine.terminal?
  end
end
