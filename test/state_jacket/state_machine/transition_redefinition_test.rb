# frozen_string_literal: true

require_relative "../../test_helper"

class StateJacket::StateMachine::TransitionRedefinitionTest < Test
  class BasicRedefinitionTest < Test
    def setup
      @system = StateJacket::TransitionSystem.new
      @system.add pending: [:approved, :rejected]
      @system.add approved: :completed
      @system.add rejected: :cancelled

      @machine = StateJacket::StateMachine.new(@system, current_state: :pending)
    end

    def test_allows_redefining_same_event_with_different_target
      # Initial definition
      @machine.on :proceed, pending: :approved
      assert_equal "approved", @machine.rules["proceed"].first["pending"]

      # Redefine with different target
      @machine.on :proceed, pending: :rejected
      assert_equal "rejected", @machine.rules["proceed"].first["pending"]

      # Ensure only one transition exists for this event/state
      assert_equal 1, @machine.rules["proceed"].count
    end

    def test_maintains_other_transitions_when_redefining
      # Define multiple transitions
      @machine.on :proceed, pending: :approved, approved: :completed
      assert_equal 2, @machine.rules["proceed"].count

      # Redefine one transition
      @machine.on :proceed, pending: :rejected

      # Should still have two transitions, but first one changed
      assert_equal 2, @machine.rules["proceed"].count
      assert_equal "rejected", @machine.rules["proceed"].find { |t| t.keys.first == "pending" }["pending"]
      assert_equal "completed", @machine.rules["proceed"].find { |t| t.keys.first == "approved" }["approved"]
    end

    def test_adding_same_definition_does_not_duplicate
      @machine.on :proceed, pending: :approved
      assert_equal 1, @machine.rules["proceed"].count

      # Adding the same transition again
      @machine.on :proceed, pending: :approved

      # Should still only have one transition
      assert_equal 1, @machine.rules["proceed"].count
    end
  end

  class ComplexRedefinitionTest < Test
    def setup
      @system = StateJacket::TransitionSystem.new
      @system.add cart: [:submitted, :abandoned]
      @system.add submitted: [:paid, :cancelled]
      @system.add paid: [:shipped, :refunded]
      @system.add shipped: [:delivered, :returned]

      @machine = StateJacket::StateMachine.new(@system, current_state: :cart)
    end

    def test_redefining_multiple_transitions
      # Initial setup
      @machine.on :process, cart: :submitted, submitted: :paid
      assert_equal 2, @machine.rules["process"].count
      assert_equal "submitted", @machine.rules["process"].find { |t| t.keys.first == "cart" }["cart"]
      assert_equal "paid", @machine.rules["process"].find { |t| t.keys.first == "submitted" }["submitted"]

      # Redefine both transitions
      @machine.on :process, cart: :abandoned, submitted: :cancelled
      assert_equal 2, @machine.rules["process"].count
      assert_equal "abandoned", @machine.rules["process"].find { |t| t.keys.first == "cart" }["cart"]
      assert_equal "cancelled", @machine.rules["process"].find { |t| t.keys.first == "submitted" }["submitted"]
    end

    def test_incremental_addition_with_redefinition
      # Add first transition
      @machine.on :process, cart: :submitted
      assert_equal 1, @machine.rules["process"].count

      # Add second transition
      @machine.on :process, submitted: :paid
      assert_equal 2, @machine.rules["process"].count

      # Redefine first transition
      @machine.on :process, cart: :abandoned
      assert_equal 2, @machine.rules["process"].count
      assert_equal "abandoned", @machine.rules["process"].find { |t| t.keys.first == "cart" }["cart"]
      assert_equal "paid", @machine.rules["process"].find { |t| t.keys.first == "submitted" }["submitted"]

      # Add third transition
      @machine.on :process, paid: :shipped
      assert_equal 3, @machine.rules["process"].count
    end
  end

  class CacheConsistencyTest < Test
    def setup
      @system = StateJacket::TransitionSystem.new
      @system.add pending: [:approved, :rejected]

      @machine = StateJacket::StateMachine.new(@system, current_state: :pending)
    end

    def test_cache_updates_on_redefinition
      # Initial definition
      @machine.on :proceed, pending: :approved
      @machine.lock

      # Verify current reachable state
      assert_equal ["approved"], @machine.reachable_states

      # Create a new machine for redefinition
      new_machine = StateJacket::StateMachine.new(@system, current_state: :pending)
      new_machine.on :proceed, pending: :rejected
      new_machine.lock

      # Verify changed reachable state
      assert_equal ["rejected"], new_machine.reachable_states
    end
  end

  class LockedBehaviorTest < Test
    def setup
      @system = StateJacket::TransitionSystem.new
      @system.add pending: [:approved, :rejected]

      @machine = StateJacket::StateMachine.new(@system, current_state: :pending)
      @machine.on :proceed, pending: :approved
    end

    def test_cannot_redefine_after_locking
      @machine.lock

      assert_raises(RuntimeError, "events cannot be added after locking") do
        @machine.on :proceed, pending: :rejected
      end
    end
  end

  class ArraySourceTest < Test
    def setup
      @system = StateJacket::TransitionSystem.new
      @system.add pending: [:approved, :rejected]
      @system.add approved: :completed
      @system.add rejected: :completed

      @machine = StateJacket::StateMachine.new(@system, current_state: :pending)
    end

    def test_array_source_for_from_states
      # Define event with array of source states
      @machine.on :complete, [:approved, :rejected] => :completed

      # Should create two transitions (one for each source state)
      assert_equal 2, @machine.rules["complete"].count
      assert_equal "completed", @machine.rules["complete"].find { |t| t.keys.first == "approved" }["approved"]
      assert_equal "completed", @machine.rules["complete"].find { |t| t.keys.first == "rejected" }["rejected"]

      # Redefine one of those transitions
      @machine.on :complete, approved: :completed

      # Should still have two transitions (redefining doesn't change anything in this case)
      assert_equal 2, @machine.rules["complete"].count
      assert_equal "completed", @machine.rules["complete"].find { |t| t.keys.first == "approved" }["approved"]
      assert_equal "completed", @machine.rules["complete"].find { |t| t.keys.first == "rejected" }["rejected"]
    end

    def test_redefinition_replaces_transition
      # Define initial event
      @machine.on :advance, pending: :approved
      assert_equal 1, @machine.rules["advance"].count
      assert_equal "approved", @machine.rules["advance"].first["pending"]

      # Redefine to a different target
      @machine.on :advance, pending: :rejected
      assert_equal 1, @machine.rules["advance"].count
      assert_equal "rejected", @machine.rules["advance"].first["pending"]
    end
  end
end
