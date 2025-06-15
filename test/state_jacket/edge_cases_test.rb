# frozen_string_literal: true

require_relative "../test_helper"

class StateJacket::EdgeCasesTest < Test
  class MatrixEdgeCasesTest < Test
    def test_empty_matrix
      matrix = StateJacket::Matrix.new
      assert_equal [], matrix.states
      assert_equal [], matrix.transitioners
      assert_equal [], matrix.terminals

      # Lock an empty matrix
      matrix.lock
      assert matrix.locked?
      assert_equal [], matrix.states
    end

    def test_nil_and_empty_values
      matrix = StateJacket::Matrix.new

      # Add nil target explicitly (creates terminal state)
      matrix.add pending: nil
      assert_equal ["pending"], matrix.states
      assert_equal [], matrix.transitioners
      assert_equal ["pending"], matrix.terminals

      # Add empty array target (this creates a transitioner with no targets)
      matrix.add active: []
      assert_equal ["active", "pending"], matrix.states.sort
      assert_equal ["active"], matrix.transitioners
      assert_equal ["pending"], matrix.terminals
    end

    def test_circular_references
      matrix = StateJacket::Matrix.new

      # Create a circular reference
      matrix.add state_a: :state_b
      matrix.add state_b: :state_c
      matrix.add state_c: :state_a

      assert_equal ["state_a", "state_b", "state_c"], matrix.states.sort
      assert_equal ["state_a", "state_b", "state_c"], matrix.transitioners.sort
      assert_equal [], matrix.terminals

      # Test allows? for circular references
      assert matrix.allows?("state_a" => "state_b")
      assert matrix.allows?("state_b" => "state_c")
      assert matrix.allows?("state_c" => "state_a")
    end

    def test_self_reference
      matrix = StateJacket::Matrix.new

      # Create a self-referential state
      matrix.add state_a: :state_a

      assert_equal ["state_a"], matrix.states
      assert_equal ["state_a"], matrix.transitioners
      assert_equal [], matrix.terminals

      # Test allows? for self-reference
      assert matrix.allows?("state_a" => "state_a")
    end
  end

  class MachineEdgeCasesTest < Test
    def setup
      @matrix = StateJacket::Matrix.new
      @matrix.add state_a: [:state_b, :state_c]
      @matrix.add state_b: :state_c
      @matrix.add state_c: :state_a
      @matrix.lock
    end

    def test_machine_with_no_events
      machine = StateJacket::Machine.new(@matrix, current_state: :state_a)
      machine.lock

      assert_equal [], machine.events
      assert_equal [], machine.triggerable_events
      assert_equal [], machine.reachable_states
    end

    def test_multiple_events_to_same_target
      machine = StateJacket::Machine.new(@matrix, current_state: :state_a)

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
      machine = StateJacket::Machine.new(@matrix, current_state: :state_a)
      machine.on :event_1, state_a: :state_b
      machine.on :event_2, state_a: :state_b
      machine.lock

      result2 = machine.trigger(:event_2)
      assert result2.successful?
      assert_equal "state_b", machine.current_state
    end

    def test_same_event_to_different_targets
      machine = StateJacket::Machine.new(@matrix, current_state: :state_a)

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
      @matrix = StateJacket::Matrix.new
      @matrix.add pending: [:approved, :rejected]
      @matrix.lock
    end

    def test_invalid_initial_state
      assert_raises(StateJacket::Machine::Error, "illegal state") do
        StateJacket::Machine.new(@matrix, current_state: :non_existent)
      end

      assert_raises(StateJacket::Machine::Error, "illegal state") do
        StateJacket::Machine.new(@matrix, current_state: nil)
      end
    end

    def test_nil_matrix
      assert_raises(StateJacket::Machine::Error, "matrix cannot be nil") do
        StateJacket::Machine.new(nil, current_state: :pending)
      end
    end

    def test_trigger_without_locking
      machine = StateJacket::Machine.new(@matrix, current_state: :pending)
      machine.on :approve, pending: :approved

      assert_raises(StateJacket::Machine::Error, "must be locked before triggering events") do
        machine.trigger(:approve)
      end
    end

    def test_add_event_after_locking
      machine = StateJacket::Machine.new(@matrix, current_state: :pending)
      machine.lock

      assert_raises(StateJacket::Machine::Error, "events cannot be added after locking") do
        machine.on :approve, pending: :approved
      end
    end

    def test_trigger_nonexistent_event
      machine = StateJacket::Machine.new(@matrix, current_state: :pending)
      machine.on :approve, pending: :approved
      machine.lock

      assert_raises(StateJacket::Machine::Error) do
        machine.trigger(:reject)
      end
    end

    def test_error_in_transition_block
      machine = StateJacket::Machine.new(@matrix, current_state: :pending)
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
      machine = StateJacket::Machine.new(@matrix, current_state: :pending)
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
      machine2 = StateJacket::Machine.new(@matrix, current_state: :pending)
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
      machine = StateJacket::Machine.new(@matrix, current_state: :pending)
      machine.on "", pending: :approved  # Empty string event
      machine.lock

      # Should be able to trigger empty string event
      result = machine.trigger("")
      assert result.successful?
      assert_equal "approved", machine.current_state
    end

    def test_whitespace_event_handling
      machine = StateJacket::Machine.new(@matrix, current_state: :pending)
      machine.on "  ", pending: :approved  # Whitespace event
      machine.on "\t", pending: :rejected   # Tab character event
      machine.lock

      assert machine.include?("  ")
      assert machine.include?("\t")
      assert machine.can_trigger?("  ")
    end

    def test_special_character_events
      machine = StateJacket::Machine.new(@matrix, current_state: :pending)
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
      machine = StateJacket::Machine.new(@matrix, current_state: :pending)

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
      machine = StateJacket::Machine.new(@matrix, current_state: :pending)
      long_event_name = "a" * 1000  # Very long event name
      machine.on long_event_name, pending: :approved
      machine.lock

      assert machine.include?(long_event_name)
      result = machine.trigger(long_event_name)
      assert result.successful?
    end

    def test_unicode_event_names
      machine = StateJacket::Machine.new(@matrix, current_state: :pending)
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
      @matrix = StateJacket::Matrix.new
      @matrix.add pending: [:approved, :rejected]
      @matrix.add approved: :completed
      @matrix.lock
    end

    def test_frozen_rules_after_locking
      machine = StateJacket::Machine.new(@matrix, current_state: :pending)
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

    def test_matrix_frozen_after_locking
      # Matrix should be locked and have consistent behavior
      assert @matrix.locked?

      # Should be able to access rules consistently
      rules1 = @matrix.rules
      rules2 = @matrix.rules
      assert_equal rules1, rules2

      # Cached values should be available when locked
      assert @matrix.cached_terminals
      assert @matrix.cached_transitioners
    end

    def test_introspection_consistency_after_multiple_operations
      machine = StateJacket::Machine.new(@matrix, current_state: :pending)
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

    def test_machine_to_h_immutability
      machine = StateJacket::Machine.new(@matrix, current_state: :pending)
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
      machine = StateJacket::Machine.new(@matrix, current_state: :pending)
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
      machine = StateJacket::Machine.new(@matrix, current_state: :pending)
      machine.on :approve, pending: :approved
      machine.lock

      # Pattern matching should work with frozen machine
      result = case machine
      in {current_state: "pending", locked: true}
        "correctly matched"
      else
        "failed to match"
      end

      assert_equal "correctly matched", result

      # Pattern matching with transition results
      transition_result = machine.trigger(:approve)

      matched_event = case transition_result
      in {event: event, status: :ok}
        event
      else
        "no match"
      end

      assert_equal "approve", matched_event
    end

    def test_error_state_consistency
      machine = StateJacket::Machine.new(@matrix, current_state: :pending)
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
      @matrix = StateJacket::Matrix.new
      @matrix.add active: [:suspended, :deactivated]
      @matrix.add suspended: :deactivated
      @matrix.add pending: :active
      @matrix.add deactivated: nil  # explicit terminal state
      @matrix.lock
    end

    def test_overlaps_with_terminal_states
      # overlaps? should now correctly handle terminal state transitions
      refute @matrix.overlaps?(active: nil), "active cannot become terminal (has outgoing transitions)"
      refute @matrix.overlaps?(suspended: nil), "suspended cannot become terminal (has outgoing transitions)"
      assert @matrix.overlaps?(deactivated: nil), "deactivated is already terminal, so overlaps with nil"

      # Test with empty array (should return false)
      refute @matrix.overlaps?(active: []), "overlaps? returns false for empty target array"
    end

    def test_match_with_terminal_states
      # match? should work correctly with terminal states
      assert @matrix.match?(deactivated: nil), "match? should work with explicit terminal states"
      refute @matrix.match?(active: nil), "active is not a terminal state"
      refute @matrix.match?(suspended: nil), "suspended is not a terminal state"
    end

    def test_allows_with_terminal_states
      # allows? should handle terminal state checks
      refute @matrix.allows?(deactivated: "active"), "terminal states cannot transition"
      refute @matrix.allows?(deactivated: "suspended"), "terminal states cannot transition"

      # Test valid transitions to terminal behavior
      assert @matrix.allows?(active: "deactivated"), "active can transition to deactivated"
      assert @matrix.allows?(suspended: "deactivated"), "suspended can transition to deactivated"
    end

    def test_terminal_state_matrix_consistency
      # Verify that states identified as terminal behave consistently
      assert @matrix.terminal?("deactivated")
      refute @matrix.transitioner?("deactivated")

      # Verify that implicit terminal states work too
      # (states that are targets but have no outgoing transitions)
      @matrix2 = StateJacket::Matrix.new
      @matrix2.add start: :finish  # 'finish' becomes an implicit terminal
      @matrix2.lock

      assert @matrix2.terminal?("finish")
      refute @matrix2.transitioner?("finish")
      assert @matrix2.match?(finish: nil)
    end

    def test_normalize_method_edge_cases
      # Test that the private normalize method handles edge cases correctly
      @test_matrix = StateJacket::Matrix.new

      # Test with array containing nil values should raise error
      assert_raises(StateJacket::Matrix::Error, "nil transition key") do
        @test_matrix.add [:valid_state, nil] => :target
      end

      # Test with empty array as from state should raise error
      assert_raises(StateJacket::Matrix::Error, "missing transition key") do
        @test_matrix.add [] => :target
      end
    end
  end

  class IntegrationEdgeCasesTest < Test
    def test_thread_safety
      # This test verifies that independent machines with the same transition matrix don't interfere
      matrix = StateJacket::Matrix.new
      matrix.add pending: [:approved, :rejected]
      matrix.add approved: :completed
      matrix.add rejected: :cancelled
      matrix.lock

      # Create two machines with the same transition matrix
      machine1 = StateJacket::Machine.new(matrix, current_state: :pending)
      machine1.on :approve, pending: :approved
      machine1.on :complete, approved: :completed
      machine1.lock

      machine2 = StateJacket::Machine.new(matrix, current_state: :pending)
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

    def test_nested_matrix
      # Test a complex nested state machine scenario

      # Main state machine for order processing
      order_matrix = StateJacket::Matrix.new
      order_matrix.add cart: [:checkout, :abandoned]
      order_matrix.add checkout: [:payment, :cancelled]
      order_matrix.add payment: [:shipping, :failed]
      order_matrix.add shipping: :delivered
      order_matrix.lock

      # Payment processor sub-system
      payment_matrix = StateJacket::Matrix.new
      payment_matrix.add pending: [:authorized, :declined]
      payment_matrix.add authorized: [:captured, :voided]
      payment_matrix.add captured: :settled
      payment_matrix.lock

      # Create main state machine
      order_machine = StateJacket::Machine.new(order_matrix, current_state: :cart)
      order_machine.on :checkout, cart: :checkout
      order_machine.on :cancel, checkout: :cancelled
      order_machine.on :process_payment, checkout: :payment
      order_machine.on :payment_failed, payment: :failed
      order_machine.on :ship, payment: :shipping
      order_machine.on :deliver, shipping: :delivered
      order_machine.lock

      # Create payment state machine
      payment_machine = StateJacket::Machine.new(payment_matrix, current_state: :pending)
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
