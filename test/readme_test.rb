# frozen_string_literal: true

require_relative "test_helper"

class ReadmeTest < Minitest::Test
  def test_turnstile_example_state_transition_system
    # Define the "rules" - what transitions are possible
    system = StateJacket::StateTransitionSystem.new
    system.add opened: [:closed, :errored] # opened can go to closed or errored
    system.add closed: [:opened, :errored] # closed can go to opened or errored
    system.add :errored                       # errored is terminal (no outgoing transitions)
    system.lock                               # lock it down - no more changes allowed

    # Introspect the system
    assert_equal({"opened" => ["closed", "errored"], "closed" => ["opened", "errored"], "errored" => nil}, system.to_h)
    assert_equal(["closed", "errored", "opened"], system.states)
    assert_equal(["closed", "opened"], system.transitioners)
    assert_equal(["errored"], system.terminators)

    # Test transition validity
    assert_equal(true, system.can_transition?(opened: :closed))
    assert_equal(true, system.can_transition?(closed: :opened))
    assert_equal(false, system.can_transition?(errored: :opened))
  end

  def test_turnstile_example_state_machine
    system = StateJacket::StateTransitionSystem.new
    system.add opened: [:closed, :errored]
    system.add closed: [:opened, :errored]
    system.add :errored
    system.lock

    # Create a machine using the system, starting in "closed" state
    machine = StateJacket::StateMachine.new(system, state: "closed")

    # Define events that trigger the transitions
    machine.on :open, closed: :opened                            # "open" event: closed → opened
    machine.on :close, opened: :closed                            # "close" event: opened → closed
    machine.on :error, [:closed, :opened] => :errored    # "error" event: any → errored
    machine.lock                                                     # lock it down (prevents changes)

    # Introspect the machine
    expected_to_h = {"open" => [{"closed" => "opened"}], "close" => [{"opened" => "closed"}], "error" => [{"closed" => "errored"}, {"opened" => "errored"}]}
    assert_equal(expected_to_h, machine.to_h)
    assert_equal(["open", "close", "error"], machine.events)
    assert_equal("closed", machine.state)

    # Check event availability
    assert_equal(true, machine.event?(:open))
    assert_equal(false, machine.event?(:foo))
    assert_equal(true, machine.can_trigger?(:open))
    assert_equal(false, machine.can_trigger?(:close))

    # Trigger transitions
    result = machine.trigger(:open)
    assert result.success?
    assert_equal("opened", result.to_state)
    assert_equal("opened", machine.state)

    machine.trigger(:close)
    assert_equal("closed", machine.state)

    # Transition with callback
    callback_executed = false
    machine.trigger(:open) do |from_state, to_state|
      callback_executed = true
      assert_equal("closed", from_state)
      assert_equal("opened", to_state)
    end
    assert(callback_executed)
    assert_equal("opened", machine.state)

    # Failed transitions return failure result
    result = machine.trigger(:open)
    assert result.failed?
    assert_equal("opened", machine.state)

    # Exception handling in callbacks
    original_state = machine.state
    begin
      machine.trigger(:close) do |from_state, to_state|
        raise "Something went wrong!"
      end
    rescue
      # State should be rolled back
    end
    assert_equal(original_state, machine.state)
  end

  def test_order_processing_workflow_example
    system = StateJacket::StateTransitionSystem.new
    system.add pending: [:processing, :cancelled]
    system.add processing: [:completed, :failed]
    system.add :completed             # terminal state (no outgoing transitions)
    system.add :cancelled             # another terminal state
    system.add failed: [:pending]  # failed orders can be retried
    system.lock                       # Always lock when done - prevents accidental modifications

    # Introspection (states are in insertion order, so we sort for predictable testing)
    assert_equal(["cancelled", "completed", "failed", "pending", "processing"], system.states.sort)
    assert_equal(["failed", "pending", "processing"], system.transitioners.sort)
    assert_equal(["cancelled", "completed"], system.terminators.sort)

    # State validation
    assert_equal(true, system.state?(:pending))
    assert_equal(false, system.state?(:invalid))
    assert_equal(true, system.transitioner?(:pending))
    assert_equal(true, system.terminator?(:completed))

    # Transition validation
    assert_equal(true, system.can_transition?(pending: :processing))
    assert_equal(false, system.can_transition?(completed: :pending))

    # Multiple target validation
    assert_equal(true, system.can_transition?(pending: [:processing, :cancelled]))
    assert_equal(false, system.can_transition?(pending: [:processing, :invalid]))

    # State machine setup
    machine = StateJacket::StateMachine.new(system, state: :pending)
    machine.on :start, pending: :processing
    machine.on :complete, processing: :completed
    machine.on :fail, processing: :failed
    machine.on :cancel, pending: :cancelled  # only pending can be cancelled
    machine.on :retry, failed: :pending
    machine.lock

    # Current state
    assert_equal("pending", machine.state)

    # Event introspection
    assert_equal(["start", "complete", "fail", "cancel", "retry"], machine.events)
    assert_equal(true, machine.event?(:start))
    assert_equal(true, machine.can_trigger?(:start))
    assert_equal(false, machine.can_trigger?(:complete))

    # Convenience methods for current state
    triggerable_events = machine.triggerable_events
    assert_includes(triggerable_events, "start")
    assert_includes(triggerable_events, "cancel")
    refute_includes(triggerable_events, "complete")

    reachable_states = machine.reachable_states
    assert_includes(reachable_states, "processing")
    assert_includes(reachable_states, "cancelled")

    assert_equal(false, machine.terminal?)
    assert_equal(:pending, machine.state_symbol)

    # Triggering events
    result = machine.trigger(:start)
    assert result.success?
    assert_equal("processing", result.to_state)
    assert_equal("processing", machine.state)

    # Events that can't be triggered return failure result
    result = machine.trigger(:start)
    assert result.failed?
  end

  def test_type_flexibility
    system = StateJacket::StateTransitionSystem.new
    system.add 1 => [2, 3]             # integers
    system.add "draft" => "published" # strings
    system.add active: :inactive   # symbols
    system.add nil => "initialized"   # even nil (becomes "")
    system.lock

    machine = StateJacket::StateMachine.new(system, state: 1)
    machine.on :next, 1 => 2
    machine.lock

    assert_equal("1", machine.state) # always normalized to string
  end

  def test_complex_transition_patterns
    system = StateJacket::StateTransitionSystem.new
    system.add draft: [:review, :archived]
    system.add review: [:published, :draft]
    system.add published: [:archived, :draft]
    system.add :archived
    system.lock

    machine = StateJacket::StateMachine.new(system, state: :draft)

    # One event, multiple possible transitions based on source state
    machine.on :advance, {draft: :review, review: :published}

    # One event, same destination from multiple sources
    machine.on :reset, [:review, :published] => :draft

    machine.lock

    # Test the workflow
    result1 = machine.trigger(:advance)
    assert result1.success?
    assert_equal("review", machine.state)

    result2 = machine.trigger(:advance)
    assert result2.success?
    assert_equal("published", machine.state)

    result3 = machine.trigger(:reset)
    assert result3.success?
    assert_equal("draft", machine.state)
  end

  def test_thread_safety_and_immutability
    system = StateJacket::StateTransitionSystem.new
    system.add a: :b
    system.lock

    # This will raise an exception
    error = assert_raises(RuntimeError) do
      system.add c: :d
    end
    assert_equal("states cannot be added after locking", error.message)

    # Same for machines
    machine = StateJacket::StateMachine.new(system, state: :a)
    machine.on :go, a: :b
    machine.lock

    error = assert_raises(RuntimeError) do
      machine.on :back, b: :a
    end
    assert_equal("events cannot be added after locking", error.message)
  end

  def test_business_logic_explicit_validation_pattern
    # Test explicit validation pattern with a mock payment processor
    test_payment_processor_class = Class.new do
      def initialize(amount, account)
        @amount = amount
        @account = account
        @machine = build_machine
      end

      def process!
        return failure("Payment invalid") unless payment_valid?
        return failure("Insufficient funds") unless sufficient_funds?

        @machine.trigger(:process) do |from, to|
          @account[:balance] -= @amount
          @account[:last_charge] = @amount
        end

        success("Payment processed")
      end

      def state
        @machine.state
      end

      private

      def payment_valid?
        @account && @account[:valid]
      end

      def sufficient_funds?
        @account[:balance] >= @amount
      end

      def build_machine
        system = StateJacket::StateTransitionSystem.new
        system.add pending: [:processed, :failed]
        system.add :processed
        system.add :failed
        system.lock

        machine = StateJacket::StateMachine.new(system, state: :pending)
        machine.on :process, pending: :processed
        machine.on :fail, pending: :failed
        machine.lock
        machine
      end

      def success(message)
        {success: true, message: message}
      end

      def failure(message)
        @machine.trigger(:fail)
        {success: false, error: message}
      end
    end

    # Test insufficient funds
    account = {balance: 50, valid: true}
    processor = test_payment_processor_class.new(100, account)
    result = processor.process!

    assert_equal(false, result[:success])
    assert_equal("Insufficient funds", result[:error])
    assert_equal("failed", processor.state)

    # Test successful payment
    account = {balance: 200, valid: true}
    processor = test_payment_processor_class.new(100, account)
    result = processor.process!

    assert_equal(true, result[:success])
    assert_equal("Payment processed", result[:message])
    assert_equal("processed", processor.state)
    assert_equal(100, account[:balance])
    assert_equal(100, account[:last_charge])
  end

  def test_e_commerce_order_processing_example
    # Simplified version of the e-commerce example
    test_order_processor_class = Class.new do
      def initialize(status)
        @status = status
        @machine = build_order_machine
      end

      def submit!
        return failure("Cannot submit") unless @machine.can_trigger?(:submit)

        @machine.trigger(:submit) do |from, to|
          @status = to
        end

        success("Order submitted")
      end

      def process_payment!
        return failure("Cannot process payment") unless @machine.can_trigger?(:pay)

        @machine.trigger(:pay) do |from, to|
          @status = to
        end

        success("Payment processed")
      end

      def ship!
        return failure("Cannot ship") unless @machine.can_trigger?(:ship)

        @machine.trigger(:ship) do |from, to|
          @status = to
        end

        success("Order shipped")
      end

      def state
        @machine.state
      end

      private

      def build_order_machine
        system = StateJacket::StateTransitionSystem.new
        system.add cart: [:submitted, :cancelled]
        system.add submitted: [:paid, :cancelled]
        system.add paid: [:shipped, :refunded]
        system.add shipped: [:delivered, :returned, :refunded]
        system.add delivered: [:returned, :refunded]
        system.add :cancelled
        system.add :refunded
        system.add :returned
        system.lock

        machine = StateJacket::StateMachine.new(system, state: @status)
        machine.on :submit, cart: :submitted
        machine.on :pay, submitted: :paid
        machine.on :ship, paid: :shipped
        machine.on :deliver, shipped: :delivered
        machine.on :cancel, [:cart, :submitted] => :cancelled
        machine.on :refund, [:paid, :shipped, :delivered] => :refunded
        machine.on :return, [:shipped, :delivered] => :returned
        machine.lock
        machine
      end

      def success(message)
        {success: true, message: message}
      end

      def failure(message)
        {success: false, error: message}
      end
    end

    processor = test_order_processor_class.new(:cart)

    # Test the workflow
    result = processor.submit!
    assert_equal(true, result[:success])
    assert_equal("submitted", processor.state)

    result = processor.process_payment!
    assert_equal(true, result[:success])
    assert_equal("paid", processor.state)

    result = processor.ship!
    assert_equal(true, result[:success])
    assert_equal("shipped", processor.state)
  end

  def test_user_account_lifecycle_example
    system = StateJacket::StateTransitionSystem.new
    system.add pending: [:active, :rejected]
    system.add active: [:suspended, :deactivated]
    system.add suspended: [:active, :deactivated]
    system.add deactivated: :active
    system.add :rejected
    system.lock

    machine = StateJacket::StateMachine.new(system, state: :pending)
    machine.on :activate, pending: :active
    machine.on :reject, pending: :rejected
    machine.on :suspend, active: :suspended
    machine.on :reactivate, [:suspended, :deactivated] => :active
    machine.on :deactivate, [:active, :suspended] => :deactivated
    machine.lock

    # Test account activation
    machine.trigger(:activate)
    assert_equal("active", machine.state)

    # Test suspension
    machine.trigger(:suspend)
    assert_equal("suspended", machine.state)

    # Test reactivation
    machine.trigger(:reactivate)
    assert_equal("active", machine.state)

    # Test deactivation
    machine.trigger(:deactivate)
    assert_equal("deactivated", machine.state)

    # Test reactivation from deactivated
    machine.trigger(:reactivate)
    assert_equal("active", machine.state)
  end

  def test_document_approval_workflow_example
    system = StateJacket::StateTransitionSystem.new
    system.add draft: [:submitted, :archived]
    system.add submitted: [:approved, :rejected, :needs_revision]
    system.add needs_revision: [:submitted, :archived]
    system.add approved: :published
    system.add published: :archived
    system.add rejected: [:draft, :archived]
    system.add :archived
    system.lock

    machine = StateJacket::StateMachine.new(system, state: :draft)
    machine.on :submit, [:draft, :needs_revision] => :submitted
    machine.on :approve, submitted: :approved
    machine.on :reject, submitted: :rejected
    machine.on :request_changes, submitted: :needs_revision
    machine.on :publish, approved: :published
    machine.on :archive, [:draft, :needs_revision, :rejected, :published] => :archived
    machine.on :revise, rejected: :draft
    machine.lock

    # Test document workflow
    machine.trigger(:submit)
    assert_equal("submitted", machine.state)

    machine.trigger(:approve)
    assert_equal("approved", machine.state)

    machine.trigger(:publish)
    assert_equal("published", machine.state)

    machine.trigger(:archive)
    assert_equal("archived", machine.state)
  end

  def test_testing_examples_from_readme
    # Test state transition system testing example
    system = StateJacket::StateTransitionSystem.new
    system.add pending: [:processing, :cancelled]
    system.add processing: [:completed, :failed]
    system.add :completed
    system.add :cancelled
    system.add failed: :pending
    system.lock

    assert_equal(%w[cancelled completed failed pending processing], system.states.sort)
    assert_equal(%w[cancelled completed], system.terminators.sort)

    assert_equal(true, system.can_transition?(pending: :processing))
    assert_equal(true, system.can_transition?(processing: :completed))
    assert_equal(true, system.can_transition?(failed: :pending))

    assert_equal(false, system.can_transition?(completed: :pending))
    assert_equal(false, system.can_transition?(cancelled: :processing))

    # Test state machine testing example
    machine = StateJacket::StateMachine.new(system, state: :pending)
    machine.on :process, pending: :processing
    machine.on :complete, processing: :completed
    machine.on :cancel, pending: :cancelled
    machine.lock

    assert_equal("pending", machine.state)

    # Test transition validity
    result = machine.trigger(:process)
    assert result.success?
    assert_equal("processing", result.to_state)
    assert_equal("processing", machine.state)

    # Test invalid transition - can't process again from processing state
    invalid_result = machine.trigger(:process)      # Can't process from processing
    assert invalid_result.failed?
    assert_equal("processing", machine.state)  # State unchanged

    # Test callback execution
    callback_executed = false

    machine = StateJacket::StateMachine.new(system, state: :pending)
    machine.on :process, pending: :processing
    machine.lock

    machine.trigger(:process) do |from, to|
      callback_executed = true
      assert_equal("pending", from)
      assert_equal("processing", to)
    end

    assert(callback_executed)

    # Test rollback on exception
    machine = StateJacket::StateMachine.new(system, state: :pending)
    machine.on :process, pending: :processing
    machine.lock

    assert_raises(StandardError) do
      machine.trigger(:process) { raise "Test error" }
    end

    assert_equal("pending", machine.state) # Rolled back
  end

  def test_hash_syntax_for_multiple_from_states
    # Verify that the hash syntax works correctly for multiple from states
    system = StateJacket::StateTransitionSystem.new
    system.add state1: [:target]
    system.add state2: [:target]
    system.add state3: [:target]
    system.add :target
    system.lock

    machine = StateJacket::StateMachine.new(system, state: :state1)
    machine.on :reset, {state1: :target, state2: :target, state3: :target}
    machine.lock

    # Should work from state1
    assert(machine.can_trigger?(:reset))
    machine.trigger(:reset)
    assert_equal("target", machine.state)

    # Test from different starting states
    machine2 = StateJacket::StateMachine.new(system, state: :state2)
    machine2.on :reset, {state1: :target, state2: :target, state3: :target}
    machine2.lock

    assert(machine2.can_trigger?(:reset))
    machine2.trigger(:reset)
    assert_equal("target", machine2.state)
  end

  def test_real_world_pattern_matching_examples
    # Test E-commerce Order Processing pattern matching
    system = StateJacket::StateTransitionSystem.new
    system.add cart: [:submitted, :cancelled]
    system.add submitted: [:paid, :cancelled]
    system.add paid: [:shipped, :refunded]
    system.add shipped: [:delivered]
    system.add :delivered
    system.add :cancelled
    system.add :refunded
    system.lock

    machine = StateJacket::StateMachine.new(system, state: :cart)
    machine.on :checkout, cart: :submitted
    machine.on :payment, submitted: :paid
    machine.on :ship, paid: :shipped
    machine.on :cancel, [:cart, :submitted] => :cancelled
    machine.lock

    # Test pattern matching with transition results
    result = machine.trigger(:checkout)
    action_taken = case result
    in { success?: true, from: "cart", to: "submitted", event: "checkout" }
      :send_confirmation_email
    in { failed?: true, from: "cart", event: "checkout" }
      :show_checkout_error
    else
      :unknown_action
    end

    assert_equal :send_confirmation_email, action_taken
    assert_equal "submitted", machine.state
  end

  def test_user_permission_pattern_matching
    # Test User Permission System pattern matching
    system = StateJacket::StateTransitionSystem.new
    system.add pending: [:active, :rejected]
    system.add active: [:premium, :suspended]
    system.add premium: [:active, :suspended]
    system.add suspended: [:active]
    system.add :rejected
    system.lock

    machine = StateJacket::StateMachine.new(system, state: :pending)
    machine.on :activate, pending: :active
    machine.on :upgrade, active: :premium
    machine.on :suspend, [:active, :premium] => :suspended
    machine.lock

    # Test permission determination based on state
    permissions = case machine
    in { state: "pending", triggerable_events: events } if events.include?("activate")
      [:view_profile, :complete_verification]
    in { state: "active", reachable_states: states } if states.include?("premium")
      [:read, :write, :comment, :upgrade_to_premium]
    in { state: "premium", terminal?: false }
      [:read, :write, :comment, :moderate, :export_data]
    in { terminal?: true }
      [:view_profile]
    else
      []
    end

    assert_includes permissions, :view_profile
    assert_includes permissions, :complete_verification
  end

  def test_api_response_formatting_pattern_matching
    # Test API Response Formatting pattern matching
    system = StateJacket::StateTransitionSystem.new
    system.add pending: [:processing, :cancelled]
    system.add processing: [:completed, :failed]
    system.add :completed
    system.add :cancelled
    system.add :failed
    system.lock

    machine = StateJacket::StateMachine.new(system, state: :pending)
    machine.on :process, pending: :processing
    machine.on :complete, processing: :completed
    machine.lock

    result = machine.trigger(:process)

    response = case [machine, result]
    in [{ state: "completed" }, { success?: true }]
      {status: "success", final: true}
    in [{ triggerable_events: events }, { success?: true, to: String => new_state }]
      {status: "success", current_state: new_state, available_actions: events}
    in [{ state: String => current }, { failure?: true, event: String => failed_event }]
      {status: "error", current_state: current, failed_event: failed_event}
    else
      {status: "unknown"}
    end

    assert_equal "success", response[:status]
    assert_equal "processing", response[:current_state]
    assert response[:available_actions].is_a?(Array)
  end

  def test_error_recovery_pattern_matching
    # Test Error Recovery Patterns pattern matching
    system = StateJacket::StateTransitionSystem.new
    system.add idle: [:processing, :failed]
    system.add processing: [:completed, :failed]
    system.add failed: [:processing, :abandoned]
    system.add :completed
    system.add :abandoned
    system.lock

    machine = StateJacket::StateMachine.new(system, state: :idle)
    machine.on :start, idle: :processing
    machine.on :complete, processing: :completed
    machine.on :fail, [:processing, :idle] => :failed
    machine.on :retry, failed: :processing
    machine.lock

    # Simulate failure and test recovery pattern
    machine.trigger(:start)
    failure_result = machine.trigger(:fail)
    attempt_count = 1

    recovery_action = case [failure_result, attempt_count]
    in [{ success?: true, to: "failed" }, count] if count < 3
      :retry_after_delay
    in [{ success?: true, to: "failed" }, count] if count >= 3
      :escalate_to_manual_review
    in [{ failure?: true }, _]
      :log_error_and_alert
    else
      :unknown_recovery
    end

    assert_equal :retry_after_delay, recovery_action
    assert_equal "failed", machine.state
  end

  def test_notification_system_pattern_matching
    # Test Notification System pattern matching
    system = StateJacket::StateTransitionSystem.new
    system.add inactive: [:active]
    system.add active: [:premium, :suspended]
    system.add premium: [:active]
    system.add :suspended
    system.lock

    machine = StateJacket::StateMachine.new(system, state: :inactive)
    machine.on :activate, inactive: :active
    machine.on :upgrade, active: :premium
    machine.on :suspend, active: :suspended
    machine.lock

    result = machine.trigger(:activate)

    notification_type = case result
    in { success?: true, from: "inactive", to: "active", event: "activate" }
      :welcome_email
    in { success?: true, to: "premium", event: "upgrade" }
      :premium_welcome
    in { success?: true, to: "suspended", event: "suspend" }
      :suspension_notice
    in { failed?: true, event: "upgrade" }
      :payment_failure
    else
      :generic_notification
    end

    assert_equal :welcome_email, notification_type
    assert_equal "active", machine.state
  end

  def test_semantic_aliases_pattern_matching
    # Test simplified pattern matching in TransitionResult
    system = StateJacket::StateTransitionSystem.new
    system.add draft: [:published, :rejected]
    system.add :published
    system.add :rejected
    system.lock

    machine = StateJacket::StateMachine.new(system, state: :draft)
    machine.on :publish, draft: :published
    machine.on :reject, draft: :rejected
    machine.lock

    result = machine.trigger(:publish)

    # Test basic pattern matching
    basic_match = case result
    in { success?: true, from: "draft", to: "published" }
      :basic_matched
    else
      :no_match
    end
    assert_equal :basic_matched, basic_match

    # Test event matching
    event_match = case result
    in { event: "publish", changed?: true }
      :event_matched
    else
      :no_match
    end
    assert_equal :event_matched, event_match

    # Test StateMachine simplified aliases
    machine_match = case machine
    in { state: "published", terminal?: true }
      :machine_matched
    else
      :no_match
    end
    assert_equal :machine_matched, machine_match

    # Test actions alias
    actions_match = case machine
    in { actions: actions, destinations: dests } if actions.empty? && dests.empty?
      :terminal_state_matched
    else
      :no_match
    end
    assert_equal :terminal_state_matched, actions_match
  end
end
