# frozen_string_literal: true

require_relative "../test_helper"

class StateJacket::EdgeCasesTest < Test
  class TransitionSystemEdgeCasesTest < Test
    def test_empty_system
      system = StateJacket::TransitionSystem.new
      assert_equal [], system.states
      assert_equal [], system.transitioners
      assert_equal [], system.terminals

      # Lock an empty system
      system.lock
      assert system.locked?
      assert_equal [], system.states
    end

    def test_nil_and_empty_values
      system = StateJacket::TransitionSystem.new

      # Add nil target explicitly (creates terminal state)
      system.add pending: nil
      assert_equal ["pending"], system.states
      assert_equal [], system.transitioners
      assert_equal ["pending"], system.terminals

      # Add empty array target (this creates a transitioner with no targets)
      system.add active: []
      assert_equal ["active", "pending"], system.states.sort
      assert_equal ["active"], system.transitioners
      assert_equal ["pending"], system.terminals
    end

    def test_circular_references
      system = StateJacket::TransitionSystem.new

      # Create a circular reference
      system.add state_a: :state_b
      system.add state_b: :state_c
      system.add state_c: :state_a

      assert_equal ["state_a", "state_b", "state_c"], system.states.sort
      assert_equal ["state_a", "state_b", "state_c"], system.transitioners.sort
      assert_equal [], system.terminals

      # Test allows? for circular references
      assert system.allows?("state_a" => "state_b")
      assert system.allows?("state_b" => "state_c")
      assert system.allows?("state_c" => "state_a")
    end

    def test_self_reference
      system = StateJacket::TransitionSystem.new

      # Create a self-referential state
      system.add state_a: :state_a

      assert_equal ["state_a"], system.states
      assert_equal ["state_a"], system.transitioners
      assert_equal [], system.terminals

      # Test allows? for self-reference
      assert system.allows?("state_a" => "state_a")
    end
  end

  class StateMachineEdgeCasesTest < Test
    def setup
      @system = StateJacket::TransitionSystem.new
      @system.add state_a: [:state_b, :state_c]
      @system.add state_b: :state_c
      @system.add state_c: :state_a
      @system.lock
    end

    def test_machine_with_no_events
      machine = StateJacket::StateMachine.new(@system, current_state: :state_a)
      machine.lock

      assert_equal [], machine.events
      assert_equal [], machine.triggerable_events
      assert_equal [], machine.reachable_states
    end

    def test_multiple_events_to_same_target
      machine = StateJacket::StateMachine.new(@system, current_state: :state_a)

      # Define two events for the same transition
      machine.on :event_1, state_a: :state_b
      machine.on :event_2, state_a: :state_b
      machine.lock

      assert_equal ["event_1", "event_2"], machine.events.sort
      assert_equal ["event_1", "event_2"], machine.triggerable_events.sort
      assert_equal ["state_b"], machine.reachable_states

      # Test triggering either event
      result1 = machine.trigger(:event_1)
      assert result1.successful?
      assert_equal "state_b", machine.current_state

      # Reset for next test
      machine = StateJacket::StateMachine.new(@system, current_state: :state_a)
      machine.on :event_1, state_a: :state_b
      machine.on :event_2, state_a: :state_b
      machine.lock

      result2 = machine.trigger(:event_2)
      assert result2.successful?
      assert_equal "state_b", machine.current_state
    end

    def test_same_event_to_different_targets
      machine = StateJacket::StateMachine.new(@system, current_state: :state_a)

      # Define one event for multiple transitions
      machine.on :multi_event, state_a: :state_b, state_b: :state_c, state_c: :state_a
      machine.lock

      assert_equal ["multi_event"], machine.events
      assert_equal ["multi_event"], machine.triggerable_events
      assert_equal ["state_b"], machine.reachable_states

      # Test triggering across all states
      result1 = machine.trigger(:multi_event)
      assert result1.successful?
      assert_equal "state_b", machine.current_state

      assert_equal ["multi_event"], machine.triggerable_events
      result2 = machine.trigger(:multi_event)
      assert result2.successful?
      assert_equal "state_c", machine.current_state

      assert_equal ["multi_event"], machine.triggerable_events
      result3 = machine.trigger(:multi_event)
      assert result3.successful?
      assert_equal "state_a", machine.current_state
    end
  end

  class ErrorHandlingEdgeCasesTest < Test
    def setup
      @system = StateJacket::TransitionSystem.new
      @system.add pending: [:approved, :rejected]
      @system.lock
    end

    def test_invalid_initial_state
      assert_raises(ArgumentError, "illegal state") do
        StateJacket::StateMachine.new(@system, current_state: :non_existent)
      end

      assert_raises(ArgumentError, "illegal state") do
        StateJacket::StateMachine.new(@system, current_state: nil)
      end
    end

    def test_nil_transition_system
      assert_raises(ArgumentError, "transition_system cannot be nil") do
        StateJacket::StateMachine.new(nil, current_state: :pending)
      end
    end

    def test_trigger_without_locking
      machine = StateJacket::StateMachine.new(@system, current_state: :pending)
      machine.on :approve, pending: :approved

      assert_raises(RuntimeError, "must be locked before triggering events") do
        machine.trigger(:approve)
      end
    end

    def test_add_event_after_locking
      machine = StateJacket::StateMachine.new(@system, current_state: :pending)
      machine.lock

      assert_raises(RuntimeError, "events cannot be added after locking") do
        machine.on :approve, pending: :approved
      end
    end

    def test_trigger_nonexistent_event
      machine = StateJacket::StateMachine.new(@system, current_state: :pending)
      machine.on :approve, pending: :approved
      machine.lock

      assert_raises(ArgumentError) do
        machine.trigger(:reject)
      end
    end

    def test_error_in_transition_block
      machine = StateJacket::StateMachine.new(@system, current_state: :pending)
      machine.on :approve, pending: :approved
      machine.lock

      result = machine.trigger(:approve) do |from, to|
        raise "Test error in transition block"
      end

      refute result.successful?
      assert_equal :error, result.status
      assert_equal "Test error in transition block", result.error.message
      assert_equal "pending", machine.current_state  # State should not change on error
    end

    def test_error_types_in_transition_block
      machine = StateJacket::StateMachine.new(@system, current_state: :pending)
      machine.on :approve, pending: :approved
      machine.lock

      # Test with StandardError subclass
      result = machine.trigger(:approve) do |from, to|
        raise ArgumentError, "Invalid argument"
      end

      refute result.successful?
      assert_equal :error, result.status
      assert_instance_of ArgumentError, result.error
      assert_equal "pending", machine.current_state

      # Create a new machine instance
      machine2 = StateJacket::StateMachine.new(@system, current_state: :pending)
      machine2.on :approve, pending: :approved
      machine2.lock

      # Test with custom error class
      custom_error = Class.new(StandardError)
      result = machine2.trigger(:approve) do |from, to|
        raise custom_error, "Custom error"
      end

      refute result.successful?
      assert_equal :error, result.status
      assert_instance_of custom_error, result.error
      assert_equal "pending", machine2.current_state
    end

    def test_empty_string_event_handling
      machine = StateJacket::StateMachine.new(@system, current_state: :pending)
      machine.on "", pending: :approved  # Empty string event
      machine.lock

      # Should be able to trigger empty string event
      result = machine.trigger("")
      assert result.successful?
      assert_equal "approved", machine.current_state
    end

    def test_whitespace_event_handling
      machine = StateJacket::StateMachine.new(@system, current_state: :pending)
      machine.on "  ", pending: :approved  # Whitespace event
      machine.on "\t", pending: :rejected   # Tab character event
      machine.lock

      assert machine.include?("  ")
      assert machine.include?("\t")
      assert machine.can_trigger?("  ")
    end

    def test_special_character_events
      machine = StateJacket::StateMachine.new(@system, current_state: :pending)
      machine.on "event-with-dashes", pending: :approved
      machine.on "event_with_underscores", pending: :rejected
      machine.on "event.with.dots", pending: :approved
      machine.on "event@with#symbols!", pending: :rejected
      machine.lock

      assert machine.include?("event-with-dashes")
      assert machine.include?("event_with_underscores")
      assert machine.include?("event.with.dots")
      assert machine.include?("event@with#symbols!")
    end

    def test_symbol_to_string_conversion_consistency
      machine = StateJacket::StateMachine.new(@system, current_state: :pending)

      # Define with symbol
      machine.on :approve, pending: :approved
      machine.lock

      # Should be able to trigger with either symbol or string
      assert machine.include?(:approve)
      assert machine.include?("approve")
      assert machine.can_trigger?(:approve)
      assert machine.can_trigger?("approve")

      result = machine.trigger("approve")  # String trigger for symbol-defined event
      assert result.successful?
      assert_equal "approved", machine.current_state
    end

    def test_very_long_event_name
      machine = StateJacket::StateMachine.new(@system, current_state: :pending)
      long_event_name = "a" * 1000  # Very long event name
      machine.on long_event_name, pending: :approved
      machine.lock

      assert machine.include?(long_event_name)
      result = machine.trigger(long_event_name)
      assert result.successful?
    end

    def test_unicode_event_names
      machine = StateJacket::StateMachine.new(@system, current_state: :pending)
      machine.on "승인", pending: :approved  # Korean characters
      machine.on "🚀", pending: :rejected    # Emoji
      machine.lock

      assert machine.include?("승인")
      assert machine.include?("🚀")

      result = machine.trigger("승인")
      assert result.successful?
      assert_equal "approved", machine.current_state
    end
  end

  class StateConsistencyAndFrozenObjectTest < Test
    def setup
      @system = StateJacket::TransitionSystem.new
      @system.add pending: [:approved, :rejected]
      @system.add approved: :completed
      @system.lock
    end

    def test_frozen_rules_after_locking
      machine = StateJacket::StateMachine.new(@system, current_state: :pending)
      machine.on :approve, pending: :approved
      machine.on :reject, pending: :rejected
      machine.lock

      # Events should be frozen after locking
      assert machine.events.frozen?

      # Individual rule arrays should be frozen
      machine.rules.values.each do |rule_array|
        assert rule_array.frozen?
        rule_array.each { |rule| assert rule.frozen? }
      end
    end

    def test_transition_system_frozen_after_locking
      # System should have frozen internal structures
      assert @system.rules.frozen?
      @system.rules.values.each do |target_array|
        assert target_array.frozen? if target_array
      end
    end

    def test_introspection_consistency_after_multiple_operations
      machine = StateJacket::StateMachine.new(@system, current_state: :pending)
      machine.on :approve, pending: :approved
      machine.on :complete, approved: :completed
      machine.lock

      # Initial state
      initial_events = machine.events.dup
      initial_triggerable = machine.triggerable_events.dup
      initial_reachable = machine.reachable_states.dup

      # Trigger an event
      machine.trigger(:approve)

      # Events should remain the same
      assert_equal initial_events, machine.events

      # But triggerable events and reachable states should change
      refute_equal initial_triggerable, machine.triggerable_events
      refute_equal initial_reachable, machine.reachable_states

      # New state should be consistent
      assert_equal "approved", machine.current_state
      assert_equal ["complete"], machine.triggerable_events
      assert_equal ["completed"], machine.reachable_states
    end

    def test_state_machine_to_h_immutability
      machine = StateJacket::StateMachine.new(@system, current_state: :pending)
      machine.on :approve, pending: :approved
      machine.lock

      # Get hash representation
      hash1 = machine.to_h
      original_rules = hash1[:rules].dup

      # Modifying returned hash shouldn't affect machine
      hash1[:current_state] = "modified"
      hash1[:rules]["new_event"] = [{"invalid" => "transition"}]

      # Get fresh hash
      hash2 = machine.to_h

      # Should be unchanged
      assert_equal "pending", hash2[:current_state]
      assert_equal original_rules, hash2[:rules]
    end

    def test_frozen_object_method_calls
      machine = StateJacket::StateMachine.new(@system, current_state: :pending)
      machine.on :approve, pending: :approved
      machine.lock

      # All these methods should work on frozen objects
      machine.current_state
      machine.events
      machine.rules
      machine.states
      machine.triggerable_events
      machine.reachable_states
      machine.finished?
      machine.locked?
      machine.include?(:approve)
      machine.can_trigger?(:approve)
      machine.to_h
      machine.deconstruct_keys([:current_state])

      # If we get here without exceptions, the test passes
      assert true
    end

    def test_pattern_matching_with_frozen_objects
      machine = StateJacket::StateMachine.new(@system, current_state: :pending)
      machine.on :approve, pending: :approved
      machine.lock

      # Pattern matching should work with frozen machine
      result = case machine
      in { current_state: "pending", locked: true }
        "correctly matched"
      else
        "failed to match"
      end

      assert_equal "correctly matched", result

      # Pattern matching with transition results
      transition_result = machine.trigger(:approve)

      matched_event = case transition_result
      in { event: event, status: :ok }
        event
      else
        "no match"
      end

      assert_equal "approve", matched_event
    end

    def test_error_state_consistency
      machine = StateJacket::StateMachine.new(@system, current_state: :pending)
      machine.on :approve, pending: :approved
      machine.lock

      original_state = machine.current_state

      # Trigger with error in block
      result = machine.trigger(:approve) do |from, to|
        raise "Simulated error"
      end

      # State should remain unchanged after error
      assert_equal original_state, machine.current_state
      refute result.successful?
      assert_equal :error, result.status
      assert_kind_of StandardError, result.error

      # Machine should still be in valid state for further operations
      assert machine.locked?
      assert machine.can_trigger?(:approve)
    end
  end

  class TerminalStateEdgeCasesTest < Test
    def setup
      @system = StateJacket::TransitionSystem.new
      @system.add active: [:suspended, :deactivated]
      @system.add suspended: :deactivated
      @system.add pending: :active
      @system.add deactivated: nil  # explicit terminal state
      @system.lock
    end

    def test_overlaps_with_terminal_states
      # overlaps? should now correctly handle terminal state transitions
      refute @system.overlaps?(active: nil), "active cannot become terminal (has outgoing transitions)"
      refute @system.overlaps?(suspended: nil), "suspended cannot become terminal (has outgoing transitions)"
      assert @system.overlaps?(deactivated: nil), "deactivated is already terminal, so overlaps with nil"

      # Test with empty array (should return false)
      refute @system.overlaps?(active: []), "overlaps? returns false for empty target array"
    end

    def test_match_with_terminal_states
      # match? should work correctly with terminal states
      assert @system.match?(deactivated: nil), "match? should work with explicit terminal states"
      refute @system.match?(active: nil), "active is not a terminal state"
      refute @system.match?(suspended: nil), "suspended is not a terminal state"
    end

    def test_allows_with_terminal_states
      # allows? should handle terminal state checks
      refute @system.allows?(deactivated: "active"), "terminal states cannot transition"
      refute @system.allows?(deactivated: "suspended"), "terminal states cannot transition"

      # Test valid transitions to terminal behavior
      assert @system.allows?(active: "deactivated"), "active can transition to deactivated"
      assert @system.allows?(suspended: "deactivated"), "suspended can transition to deactivated"
    end

    def test_terminal_state_system_consistency
      # Verify that states identified as terminal behave consistently
      assert @system.terminal?("deactivated")
      refute @system.transitioner?("deactivated")

      # Verify that implicit terminal states work too
      # (states that are targets but have no outgoing transitions)
      @system2 = StateJacket::TransitionSystem.new
      @system2.add start: :finish  # 'finish' becomes an implicit terminal
      @system2.lock

      assert @system2.terminal?("finish")
      refute @system2.transitioner?("finish")
      assert @system2.match?(finish: nil)
    end

    def test_normalize_method_edge_cases
      # Test that the private normalize method handles edge cases correctly
      @test_system = StateJacket::TransitionSystem.new

      # Test with array containing nil values should raise error
      assert_raises(ArgumentError, "nil transition key") do
        @test_system.add [:valid_state, nil] => :target
      end

      # Test with empty array as from state should raise error
      assert_raises(ArgumentError, "missing transition key") do
        @test_system.add [] => :target
      end
    end
  end

  class IntegrationEdgeCasesTest < Test
    def test_thread_safety
      # This test verifies that independent machines with the same transition system don't interfere
      system = StateJacket::TransitionSystem.new
      system.add pending: [:approved, :rejected]
      system.add approved: :completed
      system.add rejected: :cancelled
      system.lock

      # Create two machines with the same transition system
      machine1 = StateJacket::StateMachine.new(system, current_state: :pending)
      machine1.on :approve, pending: :approved
      machine1.on :complete, approved: :completed
      machine1.lock

      machine2 = StateJacket::StateMachine.new(system, current_state: :pending)
      machine2.on :reject, pending: :rejected
      machine2.on :cancel, rejected: :cancelled
      machine2.lock

      # Transition machine1
      machine1.trigger(:approve)
      assert_equal "approved", machine1.current_state
      assert_equal "pending", machine2.current_state

      # Transition machine2
      machine2.trigger(:reject)
      assert_equal "approved", machine1.current_state
      assert_equal "rejected", machine2.current_state

      # Complete machine1's lifecycle
      machine1.trigger(:complete)
      assert_equal "completed", machine1.current_state
      assert_equal "rejected", machine2.current_state

      # Complete machine2's lifecycle
      machine2.trigger(:cancel)
      assert_equal "completed", machine1.current_state
      assert_equal "cancelled", machine2.current_state
    end

    def test_nested_transition_system
      # Test a complex nested state machine scenario

      # Main state machine for order processing
      order_system = StateJacket::TransitionSystem.new
      order_system.add cart: [:checkout, :abandoned]
      order_system.add checkout: [:payment, :cancelled]
      order_system.add payment: [:shipping, :failed]
      order_system.add shipping: :delivered
      order_system.lock

      # Payment processor sub-system
      payment_system = StateJacket::TransitionSystem.new
      payment_system.add pending: [:authorized, :declined]
      payment_system.add authorized: [:captured, :voided]
      payment_system.add captured: :settled
      payment_system.lock

      # Create main state machine
      order_machine = StateJacket::StateMachine.new(order_system, current_state: :cart)
      order_machine.on :checkout, cart: :checkout
      order_machine.on :cancel, checkout: :cancelled
      order_machine.on :process_payment, checkout: :payment
      order_machine.on :payment_failed, payment: :failed
      order_machine.on :ship, payment: :shipping
      order_machine.on :deliver, shipping: :delivered
      order_machine.lock

      # Create payment state machine
      payment_machine = StateJacket::StateMachine.new(payment_system, current_state: :pending)
      payment_machine.on :authorize, pending: :authorized
      payment_machine.on :decline, pending: :declined
      payment_machine.on :capture, authorized: :captured
      payment_machine.on :void, authorized: :voided
      payment_machine.on :settle, captured: :settled
      payment_machine.lock

      # Process order
      order_machine.trigger(:checkout)
      assert_equal "checkout", order_machine.current_state

      # Process payment in sub-system
      payment_machine.trigger(:authorize)
      assert_equal "authorized", payment_machine.current_state

      # Based on payment result, continue with order
      if payment_machine.current_state == "authorized"
        payment_machine.trigger(:capture)
        order_machine.trigger(:process_payment)
      else
        order_machine.trigger(:payment_failed)
      end

      assert_equal "captured", payment_machine.current_state
      assert_equal "payment", order_machine.current_state

      # Complete order
      order_machine.trigger(:ship)
      assert_equal "shipping", order_machine.current_state

      order_machine.trigger(:deliver)
      assert_equal "delivered", order_machine.current_state

      # Verify both machines reached their final states independently
      assert payment_machine.can_trigger?(:settle)
      refute order_machine.can_trigger?(:deliver)
    end
  end
end
