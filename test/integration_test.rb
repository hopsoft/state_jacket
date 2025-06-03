# frozen_string_literal: true

require_relative "test_helper"

class IntegrationTest < Minitest::Test
  def test_door_lock_system
    # Real-world door lock system
    transitions = StateJacket::StateTransitionSystem.new
    transitions.add locked: [:unlocked, :error]
    transitions.add unlocked: [:locked, :open, :error]
    transitions.add open: [:unlocked, :error]
    transitions.add error: [:locked]

    door = StateJacket::StateMachine.new(transitions, state: :locked)
    door.on :unlock, locked: :unlocked
    door.on :lock, unlocked: :locked
    door.on :open_door, unlocked: :open
    door.on :close_door, open: :unlocked
    door.on :malfunction, {locked: :error, unlocked: :error, open: :error}
    door.on :reset, error: :locked
    door.lock

    # Normal operation flow
    door.trigger(:unlock)
    assert door.state == "unlocked"

    door.trigger(:open_door)
    assert door.state == "open"

    door.trigger(:close_door)
    assert door.state == "unlocked"

    door.trigger(:lock)
    assert door.state == "locked"

    # Error recovery
    door.trigger(:unlock)
    door.trigger(:malfunction)
    assert door.state == "error"

    door.trigger(:reset)
    assert door.state == "locked"
  end

  def test_user_account_lifecycle
    # User account state management
    transitions = StateJacket::StateTransitionSystem.new
    transitions.add pending: [:active, :rejected]
    transitions.add active: [:suspended, :deactivated]
    transitions.add suspended: [:active, :deactivated]
    transitions.add deactivated: [:active]
    transitions.add rejected: []

    account = StateJacket::StateMachine.new(transitions, state: :pending)
    account.on :approve, pending: :active
    account.on :reject, pending: :rejected
    account.on :suspend, active: :suspended
    account.on :deactivate, {active: :deactivated, suspended: :deactivated}
    account.on :reactivate, {suspended: :active, deactivated: :active}
    account.lock

    # Approval process
    account.trigger(:approve)
    assert account.state == "active"

    # Moderation actions
    account.trigger(:suspend)
    assert account.state == "suspended"

    account.trigger(:reactivate)
    assert account.state == "active"

    # Account closure
    account.trigger(:deactivate)
    assert account.state == "deactivated"

    account.trigger(:reactivate)
    assert account.state == "active"
  end

  def test_order_processing_workflow
    # E-commerce order processing
    transitions = StateJacket::StateTransitionSystem.new
    transitions.add draft: [:submitted, :cancelled]
    transitions.add submitted: [:confirmed, :cancelled]
    transitions.add confirmed: [:processing, :cancelled]
    transitions.add processing: [:shipped, :cancelled, :failed]
    transitions.add shipped: [:delivered, :returned]
    transitions.add delivered: [:returned, :completed]
    transitions.add completed: []
    transitions.add cancelled: []
    transitions.add failed: [:processing, :cancelled]
    transitions.add returned: [:refunded, :reshipped]
    transitions.add refunded: []
    transitions.add reshipped: [:delivered, :returned]

    order = StateJacket::StateMachine.new(transitions, state: :draft)
    order.on :submit, draft: :submitted
    order.on :confirm, submitted: :confirmed
    order.on :start_processing, confirmed: :processing
    order.on :ship, processing: :shipped
    order.on :deliver, shipped: :delivered
    order.on :complete, delivered: :completed
    order.on :cancel, {draft: :cancelled, submitted: :cancelled, confirmed: :cancelled, processing: :cancelled}
    order.on :fail_processing, processing: :failed
    order.on :retry_processing, failed: :processing
    order.on :return_item, {shipped: :returned, delivered: :returned}
    order.on :refund, returned: :refunded
    order.on :reship, returned: :reshipped
    order.lock

    # Happy path
    order.trigger(:submit)
    assert order.state == "submitted"

    order.trigger(:confirm)
    assert order.state == "confirmed"

    order.trigger(:start_processing)
    assert order.state == "processing"

    order.trigger(:ship)
    assert order.state == "shipped"

    order.trigger(:deliver)
    assert order.state == "delivered"

    order.trigger(:complete)
    assert order.state == "completed"

    # Test that completed orders can't be modified
    assert !order.can_trigger?(:return_item)
    assert !order.can_trigger?(:cancel)
  end

  def test_workflow_with_callbacks
    # Test state machine with business logic callbacks
    transitions = StateJacket::StateTransitionSystem.new
    transitions.add inactive: [:active]
    transitions.add active: [:inactive, :premium]
    transitions.add premium: [:active, :inactive]

    service = StateJacket::StateMachine.new(transitions, state: :inactive)
    service.on :activate, inactive: :active
    service.on :deactivate, {active: :inactive, premium: :inactive}
    service.on :upgrade, active: :premium
    service.on :downgrade, premium: :active
    service.lock

    # Track state changes with callbacks
    state_changes = []

    service.trigger(:activate) do |from, to|
      state_changes << {from: from, to: to, action: "user_activated"}
    end

    service.trigger(:upgrade) do |from, to|
      state_changes << {from: from, to: to, action: "subscription_upgraded"}
    end

    service.trigger(:downgrade) do |from, to|
      state_changes << {from: from, to: to, action: "subscription_downgraded"}
    end

    expected_changes = [
      {from: "inactive", to: "active", action: "user_activated"},
      {from: "active", to: "premium", action: "subscription_upgraded"},
      {from: "premium", to: "active", action: "subscription_downgraded"}
    ]

    assert state_changes == expected_changes
    assert service.state == "active"
  end

  def test_multiple_state_machines_coordination
    # Test coordination between multiple state machines

    # User authentication state
    auth_transitions = StateJacket::StateTransitionSystem.new
    auth_transitions.add logged_out: [:logged_in]
    auth_transitions.add logged_in: [:logged_out]

    auth = StateJacket::StateMachine.new(auth_transitions, state: :logged_out)
    auth.on :login, logged_out: :logged_in
    auth.on :logout, logged_in: :logged_out
    auth.lock

    # Session state
    session_transitions = StateJacket::StateTransitionSystem.new
    session_transitions.add inactive: [:active]
    session_transitions.add active: [:inactive, :expired]
    session_transitions.add expired: []

    session = StateJacket::StateMachine.new(session_transitions, state: :inactive)
    session.on :start, inactive: :active
    session.on :expire, active: :expired
    session.on :end, active: :inactive
    session.lock

    # Coordinate state changes
    auth.trigger(:login) do |from, to|
      session.trigger(:start) if to == "logged_in"
    end

    assert auth.state == "logged_in"
    assert session.state == "active"

    auth.trigger(:logout) do |from, to|
      session.trigger(:end) if to == "logged_out" && session.can_trigger?(:end)
    end

    assert auth.state == "logged_out"
    assert session.state == "inactive"
  end

  def test_state_machine_serialization
    # Test that state machines can be serialized/deserialized
    transitions = StateJacket::StateTransitionSystem.new
    transitions.add start: [:middle, :end]
    transitions.add middle: [:end]
    transitions.add end: []

    machine = StateJacket::StateMachine.new(transitions, state: :start)
    machine.on :advance, start: :middle
    machine.on :skip, start: :end
    machine.on :finish, middle: :end
    machine.lock

    # Simulate serialization by capturing state
    serialized_state = {
      current_state: machine.state,
      events: machine.events,
      triggers: machine.to_h
    }

    machine.trigger(:advance)
    assert machine.state == "middle"

    # Verify we can inspect the serialized data
    assert serialized_state[:current_state] == "start"
    assert serialized_state[:events].sort == ["advance", "finish", "skip"]
    assert serialized_state[:triggers]["advance"] == [{"start" => "middle"}]
  end

  def test_error_handling_in_real_workflow
    # Test comprehensive error handling in a real workflow
    transitions = StateJacket::StateTransitionSystem.new
    transitions.add idle: [:working, :error]
    transitions.add working: [:idle, :completed, :error]
    transitions.add completed: [:idle]
    transitions.add error: [:idle]

    processor = StateJacket::StateMachine.new(transitions, state: :idle)
    processor.on :start_work, idle: :working
    processor.on :complete_work, working: :completed
    processor.on :reset, {completed: :idle, error: :idle}
    processor.on :error_occurred, {idle: :error, working: :error}
    processor.lock

    # Test error during processing
    processor.trigger(:start_work)

    begin
      processor.trigger(:complete_work) do |from, to|
        raise StandardError.new("Processing failed")
      end
    rescue
      # State should not have changed due to error
      assert processor.state == "working"

      # Handle the error by transitioning to error state
      processor.trigger(:error_occurred)
      assert processor.state == "error"

      # Recover from error
      processor.trigger(:reset)
      assert processor.state == "idle"
    end
  end
end
