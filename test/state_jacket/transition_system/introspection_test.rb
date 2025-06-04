# frozen_string_literal: true

require_relative "../../test_helper"

class StateJacket::TransitionSystem::IntrospectionTest < Test
  class ApprovalsTest < Test
    def setup
      @system = StateJacket::TransitionSystem.new
      @system.add pending: [:approved, :rejected]
      @system.lock
    end

    def test_to_h
      expected = {
        locked: true,
        states: ["pending", "approved", "rejected"],
        transitioners: ["pending"],
        terminals: ["approved", "rejected"],
        rules: {
          "pending" => ["approved", "rejected"],
          "approved" => nil,
          "rejected" => nil
        }
      }
      assert_equal expected, @system.to_h
    end

    def test_states
      assert_equal ["pending", "approved", "rejected"], @system.states
    end

    def test_transitioners
      assert_equal ["pending"], @system.transitioners
    end

    def test_terminals
      assert_equal ["approved", "rejected"], @system.terminals
    end

    def test_locked_status_and_idempotency
      system = StateJacket::TransitionSystem.new
      refute system.locked?, "System should not be locked initially"

      # First lock
      locked_system_ref1 = system.lock
      assert system.locked?, "System should be locked after calling lock for the first time"
      assert_same system, locked_system_ref1, "lock should return self"

      # Second lock (idempotency check)
      locked_system_ref2 = system.lock
      assert system.locked?, "System should still be locked after calling lock for the second time"
      assert_same system, locked_system_ref2, "lock should return self on subsequent calls"
    end

    def test_state_predicate
      assert @system.include?("pending")
      assert @system.include?(:approved) # tests symbol conversion
      assert @system.include?("rejected")
      refute @system.include?("non_existent_state")
    end

    def test_terminal_predicate
      assert @system.terminal?("approved")
      assert @system.terminal?(:rejected)
      refute @system.terminal?("pending")
      refute @system.terminal?("non_existent_state")
    end

    def test_transitioner_predicate
      assert @system.transitioner?("pending")
      refute @system.transitioner?(:approved)
      refute @system.transitioner?("rejected")
      refute @system.transitioner?("non_existent_state")
    end

    def test_match_transition_behavior
      # Tests ArgumentErrors first
      assert_raises(ArgumentError, "transition cannot be empty") do
        @system.match?({})
      end
      assert_raises(ArgumentError, "transition must contain exactly one key-value pair") do
        @system.match?({pending: :approved, foo: :bar})
      end

      # Test valid transitions
      assert @system.match?(pending: [:approved, :rejected])

      # Test invalid transitions (to state doesn't exactly match)
      refute @system.match?(pending: :approved), "Should be false because [:approved] != [:approved, :rejected]"
      refute @system.match?(pending: :rejected), "Should be false because [:rejected] != [:approved, :rejected]"
      refute @system.match?(pending: [:rejected, :approved]), "Should be false because order of 'to' states matters for exact match"

      # Test transitions from a terminal state (always invalid as it has no outgoing transitions defined)
      refute @system.match?(approved: :pending)

      # Test transitions to a non-existent state
      refute @system.match?(pending: :non_existent_state)
      refute @system.match?(pending: [:approved, :non_existent_state])

      # Test transition from a non-existent state
      refute @system.match?(non_existent_state: :approved)

      # Tests for multiple 'from' states
      # Valid: one of the 'from' states can make the transition
      assert @system.match?([:pending, :approved] => [:approved, :rejected]), "Valid if any 'from' state matches"
      assert @system.match?([:approved, :pending] => [:approved, :rejected]), "Valid if any 'from' state matches (order independent)"
      assert @system.match?([:pending, :non_existent_state] => [:approved, :rejected]), "Valid if one 'from' is good, other non-existent"

      # Invalid: none of the 'from' states can make the transition
      refute @system.match?([:approved, :rejected] => [:approved, :rejected]), "Invalid if no 'from' state matches target"
      refute @system.match?([:non_existent_state, :another_non_existent] => [:approved, :rejected]), "Invalid if all 'from' states are non-existent"
      refute @system.match?([:pending, :approved] => :some_other_target), "Invalid if target doesn't match for any 'from' state"
      refute @system.match?([:pending, :approved] => [:approved]), "Invalid if target array is subset and doesn't exactly match"
    end

    def test_allows_transition_behavior
      # Tests ArgumentErrors first
      assert_raises(ArgumentError, "transition cannot be empty") do
        @system.allows?({})
      end
      assert_raises(ArgumentError, "transition must contain exactly one key-value pair") do
        @system.allows?({pending: :approved, foo: :bar})
      end

      # Test allowed individual transitions
      assert @system.allows?(pending: "approved")
      assert @system.allows?(pending: :rejected)
      assert @system.allows?("pending" => :approved)  # Mixed string/symbol

      # Test disallowed transitions
      refute @system.allows?(approved: "pending"), "Terminal state cannot transition"
      refute @system.allows?(rejected: "pending"), "Terminal state cannot transition"
      refute @system.allows?(pending: "non_existent"), "Cannot transition to non-existent state"
      refute @system.allows?(non_existent: "approved"), "Non-existent state cannot transition"

      # Test transitions that don't exist in the defined rules
      refute @system.allows?(approved: "rejected"), "No such transition defined"
    end

    def test_overlaps_transition_behavior
      # Tests ArgumentErrors first
      assert_raises(ArgumentError, "transition cannot be empty") do
        @system.overlaps?({})
      end
      assert_raises(ArgumentError, "transition must contain exactly one key-value pair") do
        @system.overlaps?({pending: :approved, foo: :bar})
      end

      # Test basic overlap behavior (any from state to any to state)
      assert @system.overlaps?(pending: [:approved, :rejected])
      assert @system.overlaps?(pending: :approved), "Single to-state should overlap"
      assert @system.overlaps?(pending: :rejected), "Single to-state should overlap"
      assert @system.overlaps?(pending: [:approved, :non_existent]), "Should overlap if any target is valid"

      # Test with multiple from states
      assert @system.overlaps?([:pending, :approved] => :approved), "Should overlap if any from-state has valid transition"
      assert @system.overlaps?([:pending, :non_existent] => :approved), "Should overlap if one from-state is valid"

      # Test no overlap cases
      refute @system.overlaps?(approved: "pending"), "Terminal state cannot transition"
      refute @system.overlaps?(rejected: "pending"), "Terminal state cannot transition"
      refute @system.overlaps?(pending: "non_existent"), "Cannot overlap with non-existent state"
      refute @system.overlaps?(non_existent: "approved"), "Non-existent from-state cannot overlap"
      refute @system.overlaps?([:approved, :rejected] => :pending), "No valid from-states"

      # Demonstrate difference from match? - overlaps? is more permissive
      refute @system.match?(pending: :approved), "match? requires exact rule"
      assert @system.overlaps?(pending: :approved), "overlaps? allows partial overlap"
    end

    def test_deconstruct_keys
      expected_subset = {
        states: ["pending", "approved", "rejected"],
        locked: true
      }
      assert_equal expected_subset, @system.deconstruct_keys([:states, :locked])

      # Test with nil or empty array (should return full hash)
      assert_equal @system.to_h, @system.deconstruct_keys(nil)
      assert_equal @system.to_h, @system.deconstruct_keys([])
    end
  end

  class RailwayTest < Test
    def setup
      @system = StateJacket::TransitionSystem.new
      @system.add station_a: [:station_b, :station_c]
      @system.add station_b: :station_c
      @system.lock
    end

    def test_to_h
      expected = {
        locked: true,
        states: ["station_a", "station_b", "station_c"],
        transitioners: ["station_a", "station_b"],
        terminals: ["station_c"],
        rules: {
          "station_a" => ["station_b", "station_c"],
          "station_b" => ["station_c"],
          "station_c" => nil
        }
      }
      assert_equal expected, @system.to_h
    end

    def test_states
      assert_equal ["station_a", "station_b", "station_c"], @system.states
    end

    def test_transitioners
      assert_equal ["station_a", "station_b"], @system.transitioners
    end

    def test_terminals
      assert_equal ["station_c"], @system.terminals
    end

    def test_locked_status_and_idempotency
      system = StateJacket::TransitionSystem.new
      refute system.locked?, "System should not be locked initially"

      locked_system_ref1 = system.lock
      assert system.locked?, "System should be locked after first call to lock"
      assert_same system, locked_system_ref1, "lock should return self"

      locked_system_ref2 = system.lock
      assert system.locked?, "System should remain locked after second call to lock"
      assert_same system, locked_system_ref2, "lock should return self on subsequent calls (idempotency)"
    end

    def test_state_predicate
      assert @system.include?("station_a")
      assert @system.include?(:station_b)
      assert @system.include?("station_c")
      refute @system.include?("station_d")
    end

    def test_terminal_predicate
      assert @system.terminal?("station_c")
      refute @system.terminal?("station_a")
      refute @system.terminal?("station_b")
    end

    def test_transitioner_predicate
      assert @system.transitioner?("station_a")
      assert @system.transitioner?("station_b")
      refute @system.transitioner?("station_c")
    end

    def test_match_transition_behavior
      assert_raises(ArgumentError) { @system.match?({}) }
      assert_raises(ArgumentError) { @system.match?({station_a: :station_b, station_b: :station_c}) }

      # Valid transitions
      assert @system.match?(station_a: [:station_b, :station_c])
      assert @system.match?(station_b: :station_c), "Single 'to' state normalizes to an array"
      assert @system.match?(station_b: [:station_c]), "Single 'to' state in array normalizes correctly"

      # Invalid transitions (to state doesn't exactly match)
      refute @system.match?(station_a: :station_b), "Should be false: [:station_b] != [:station_b, :station_c]"
      refute @system.match?(station_a: [:station_b]), "Should be false: [:station_b] != [:station_b, :station_c]"
      refute @system.match?(station_a: :station_c)
      refute @system.match?(station_a: [:station_c])
      refute @system.match?(station_a: [:station_c, :station_b]), "Order matters"

      # Invalid: from a terminal state
      refute @system.match?(station_c: :station_a)

      # Invalid: to a non-existent state
      refute @system.match?(station_a: :station_d)
    end

    def test_allows_transition_behavior
      # Tests ArgumentErrors first
      assert_raises(ArgumentError, "transition cannot be empty") do
        @system.allows?({})
      end
      assert_raises(ArgumentError, "transition must contain exactly one key-value pair") do
        @system.allows?({station_a: :station_b, station_b: :station_c})
      end

      # Test allowed individual transitions
      assert @system.allows?(station_a: "station_b")
      assert @system.allows?(station_a: :station_c)
      assert @system.allows?("station_b" => :station_c)
      assert @system.allows?(station_b: "station_c")  # Mixed string/symbol

      # Test disallowed transitions
      refute @system.allows?(station_c: "station_a"), "Terminal state cannot transition"
      refute @system.allows?(station_a: "station_d"), "Cannot transition to non-existent state"
      refute @system.allows?(station_d: "station_a"), "Non-existent state cannot transition"

      # Test transitions that aren't defined in the rules
      refute @system.allows?(station_c: "station_b"), "No such transition defined"
    end

    def test_overlaps_transition_behavior
      # Tests ArgumentErrors first
      assert_raises(ArgumentError, "transition cannot be empty") do
        @system.overlaps?({})
      end
      assert_raises(ArgumentError, "transition must contain exactly one key-value pair") do
        @system.overlaps?({station_a: :station_b, station_b: :station_c})
      end

      # Test basic overlap behavior
      assert @system.overlaps?(station_a: [:station_b, :station_c])
      assert @system.overlaps?(station_a: :station_b), "Single to-state should overlap"
      assert @system.overlaps?(station_a: :station_c), "Single to-state should overlap"
      assert @system.overlaps?(station_b: :station_c)
      assert @system.overlaps?(station_a: [:station_b, :station_d]), "Should overlap if any target is valid"

      # Test with multiple from states
      assert @system.overlaps?([:station_a, :station_b] => :station_c), "Both can reach station_c"
      assert @system.overlaps?([:station_a, :station_c] => :station_b), "station_a can reach station_b"

      # Test no overlap cases
      refute @system.overlaps?(station_c: "station_a"), "Terminal state cannot transition"
      refute @system.overlaps?(station_a: "station_d"), "Cannot overlap with non-existent state"
      refute @system.overlaps?(station_d: "station_a"), "Non-existent from-state cannot overlap"

      # Demonstrate difference from match? - overlaps? is more permissive
      refute @system.match?(station_a: :station_b), "match? requires exact rule"
      assert @system.overlaps?(station_a: :station_b), "overlaps? allows partial overlap"
    end

    def test_overlaps_with_terminal_state_transitions
      # Test overlaps? with nil target (terminal state)
      refute @system.overlaps?(station_a: nil), "station_a cannot become terminal (has outgoing transitions)"
      refute @system.overlaps?(station_b: nil), "station_b cannot become terminal (has outgoing transitions)"
      assert @system.overlaps?(station_c: nil), "station_c is already terminal, so overlaps with nil"

      # Test with empty array target
      refute @system.overlaps?(station_a: []), "overlaps? returns false for empty target array"
    end

    def test_deconstruct_keys
      expected_subset = {
        transitioners: ["station_a", "station_b"],
        terminals: ["station_c"]
      }
      assert_equal expected_subset, @system.deconstruct_keys([:transitioners, :terminals])
      assert_equal @system.to_h, @system.deconstruct_keys(nil)
    end
  end

  class EcommerceTest < Test
    def setup
      @system = StateJacket::TransitionSystem.new
      @system.add cart: [:submitted, :abandoned]
      @system.add submitted: [:paid, :cancelled]
      @system.add paid: :shipped
      @system.add shipped: :delivered
      @system.lock
    end

    def test_to_h
      expected = {
        locked: true,
        states: ["cart", "submitted", "abandoned", "paid", "cancelled", "shipped", "delivered"],
        transitioners: ["cart", "submitted", "paid", "shipped"],
        terminals: ["abandoned", "cancelled", "delivered"],
        rules: {
          "cart" => ["submitted", "abandoned"],
          "submitted" => ["paid", "cancelled"],
          "abandoned" => nil,
          "paid" => ["shipped"],
          "cancelled" => nil,
          "shipped" => ["delivered"],
          "delivered" => nil
        }
      }
      assert_equal expected, @system.to_h
    end

    def test_states
      expected_states = ["cart", "submitted", "abandoned", "paid", "cancelled", "shipped", "delivered"]
      assert_equal expected_states, @system.states
    end

    def test_transitioners
      expected_transitioners = ["cart", "submitted", "paid", "shipped"]
      assert_equal expected_transitioners, @system.transitioners
    end

    def test_terminals
      expected_terminals = ["abandoned", "cancelled", "delivered"]
      assert_equal expected_terminals, @system.terminals
    end

    def test_locked_status_and_idempotency
      system = StateJacket::TransitionSystem.new
      refute system.locked?, "System should not be locked initially"

      locked_system_ref1 = system.lock
      assert system.locked?, "System should be locked after first call to lock"
      assert_same system, locked_system_ref1, "lock should return self"

      locked_system_ref2 = system.lock
      assert system.locked?, "System should remain locked after second call to lock"
      assert_same system, locked_system_ref2, "lock should return self on subsequent calls (idempotency)"
    end

    def test_state_predicate
      assert @system.include?(:cart)
      assert @system.include?(:delivered)
      refute @system.include?(:unknown_state)
    end

    def test_terminal_predicate
      assert @system.terminal?(:abandoned)
      assert @system.terminal?(:cancelled)
      assert @system.terminal?(:delivered)
      refute @system.terminal?(:cart)
      refute @system.terminal?(:submitted)
    end

    def test_transitioner_predicate
      assert @system.transitioner?(:cart)
      assert @system.transitioner?(:submitted)
      assert @system.transitioner?(:paid)
      assert @system.transitioner?(:shipped)
      refute @system.transitioner?(:abandoned)
      refute @system.transitioner?(:delivered)
    end

    def test_match_transition_behavior
      assert_raises(ArgumentError) { @system.match?({}) }
      assert_raises(ArgumentError) { @system.match?({cart: :submitted, submitted: :paid}) }

      # Valid transitions
      assert @system.match?(cart: [:submitted, :abandoned])
      assert @system.match?(submitted: [:paid, :cancelled])
      assert @system.match?(paid: :shipped)
      assert @system.match?(paid: [:shipped])
      assert @system.match?(shipped: :delivered)
      assert @system.match?(shipped: [:delivered])

      # Invalid transitions (to state doesn't exactly match)
      refute @system.match?(cart: :submitted), "Should be false: [:submitted] != [:submitted, :abandoned]"
      refute @system.match?(cart: [:submitted])
      refute @system.match?(submitted: :paid)
      refute @system.match?(submitted: [:paid])

      # Invalid: from a terminal state
      refute @system.match?(abandoned: :cart)
      refute @system.match?(delivered: :shipped)

      # Invalid: to a non-existent state
      refute @system.match?(cart: :unknown_state)
    end

    def test_allows_transition_behavior
      # Tests ArgumentErrors first
      assert_raises(ArgumentError, "transition cannot be empty") do
        @system.allows?({})
      end
      assert_raises(ArgumentError, "transition must contain exactly one key-value pair") do
        @system.allows?({cart: :submitted, submitted: :paid})
      end

      # Test allowed individual transitions
      assert @system.allows?(cart: "submitted")
      assert @system.allows?(cart: :abandoned)
      assert @system.allows?("submitted" => :paid)
      assert @system.allows?(submitted: "cancelled")
      assert @system.allows?("paid" => "shipped")
      assert @system.allows?(shipped: :delivered)

      # Test disallowed transitions
      refute @system.allows?(abandoned: "cart"), "Terminal state cannot transition"
      refute @system.allows?(delivered: "shipped"), "Terminal state cannot transition"
      refute @system.allows?(cart: "unknown_state"), "Cannot transition to non-existent state"
      refute @system.allows?(unknown_state: "cart"), "Non-existent state cannot transition"

      # Test transitions that aren't defined in the rules
      refute @system.allows?(delivered: "abandoned"), "No such transition defined"
      refute @system.allows?(cancelled: "paid"), "No such transition defined"
    end

    def test_overlaps_transition_behavior
      # Tests ArgumentErrors first
      assert_raises(ArgumentError, "transition cannot be empty") do
        @system.overlaps?({})
      end
      assert_raises(ArgumentError, "transition must contain exactly one key-value pair") do
        @system.overlaps?({cart: :submitted, submitted: :paid})
      end

      # Test basic overlap behavior
      assert @system.overlaps?(cart: [:submitted, :abandoned])
      assert @system.overlaps?(cart: :submitted), "Single to-state should overlap"
      assert @system.overlaps?(cart: :abandoned), "Single to-state should overlap"
      assert @system.overlaps?(submitted: [:paid, :cancelled])
      assert @system.overlaps?(cart: [:submitted, :unknown]), "Should overlap if any target is valid"

      # Test with multiple from states
      assert @system.overlaps?([:cart, :submitted] => :paid), "submitted can reach paid"
      assert @system.overlaps?([:cart, :submitted] => [:submitted, :paid]), "Multiple valid overlaps"

      # Test no overlap cases
      refute @system.overlaps?(abandoned: "cart"), "Terminal state cannot transition"
      refute @system.overlaps?(delivered: "shipped"), "Terminal state cannot transition"
      refute @system.overlaps?(cart: "unknown_state"), "Cannot overlap with non-existent state"
      refute @system.overlaps?(unknown_state: "cart"), "Non-existent from-state cannot overlap"

      # Demonstrate difference from match? - overlaps? is more permissive
      refute @system.match?(cart: :submitted), "match? requires exact rule"
      assert @system.overlaps?(cart: :submitted), "overlaps? allows partial overlap"
    end

    def test_overlaps_with_terminal_state_transitions
      # Test overlaps? with nil target (terminal state)
      refute @system.overlaps?(cart: nil), "cart cannot become terminal (has outgoing transitions)"
      refute @system.overlaps?(submitted: nil), "submitted cannot become terminal (has outgoing transitions)"
      assert @system.overlaps?(abandoned: nil), "abandoned is already terminal, so overlaps with nil"
      assert @system.overlaps?(delivered: nil), "delivered is already terminal, so overlaps with nil"

      # Test that match? works correctly with terminal states
      assert @system.match?(abandoned: nil), "match? should work with terminal states"
      assert @system.match?(delivered: nil), "match? should work with terminal states"
    end

    def test_deconstruct_keys
      keys_to_get = [:states, :terminals, :locked]
      expected_subset = {
        states: ["cart", "submitted", "abandoned", "paid", "cancelled", "shipped", "delivered"],
        terminals: ["abandoned", "cancelled", "delivered"],
        locked: true
      }
      assert_equal expected_subset, @system.deconstruct_keys(keys_to_get)
      assert_equal @system.to_h, @system.deconstruct_keys(nil)
    end
  end

  class OrderProcessorTest < Test
    def setup
      @system = StateJacket::TransitionSystem.new
      @system.add cart: [:submitted, :abandoned]
      @system.add submitted: [:paid, :cancelled]
      @system.add paid: [:shipped, :refunded]
      @system.add shipped: [:delivered, :returned]
      @system.lock
    end

    def test_to_h
      expected = {
        locked: true,
        states: ["cart", "submitted", "abandoned", "paid", "cancelled", "shipped", "refunded", "delivered", "returned"],
        transitioners: ["cart", "submitted", "paid", "shipped"],
        terminals: ["abandoned", "cancelled", "refunded", "delivered", "returned"],
        rules: {
          "cart" => ["submitted", "abandoned"],
          "submitted" => ["paid", "cancelled"],
          "abandoned" => nil,
          "paid" => ["shipped", "refunded"],
          "cancelled" => nil,
          "shipped" => ["delivered", "returned"],
          "refunded" => nil,
          "delivered" => nil,
          "returned" => nil
        }
      }
      assert_equal expected, @system.to_h
    end

    def test_states
      expected_states = ["cart", "submitted", "abandoned", "paid", "cancelled", "shipped", "refunded", "delivered", "returned"]
      assert_equal expected_states, @system.states
    end

    def test_transitioners
      expected_transitioners = ["cart", "submitted", "paid", "shipped"]
      assert_equal expected_transitioners, @system.transitioners
    end

    def test_terminals
      expected_terminals = ["abandoned", "cancelled", "refunded", "delivered", "returned"]
      assert_equal expected_terminals, @system.terminals
    end

    def test_locked_status_and_idempotency
      system = StateJacket::TransitionSystem.new
      refute system.locked?, "System should not be locked initially"

      locked_system_ref1 = system.lock
      assert system.locked?, "System should be locked after first call to lock"
      assert_same system, locked_system_ref1, "lock should return self"

      locked_system_ref2 = system.lock
      assert system.locked?, "System should remain locked after second call to lock"
      assert_same system, locked_system_ref2, "lock should return self on subsequent calls (idempotency)"
    end

    def test_state_predicate
      assert @system.include?(:cart)
      assert @system.include?(:returned)
      refute @system.include?(:processing)
    end

    def test_terminal_predicate
      assert @system.terminal?(:abandoned)
      assert @system.terminal?(:refunded)
      assert @system.terminal?(:returned)
      refute @system.terminal?(:cart)
      refute @system.terminal?(:paid)
    end

    def test_transitioner_predicate
      assert @system.transitioner?(:cart)
      assert @system.transitioner?(:paid)
      refute @system.transitioner?(:abandoned)
      refute @system.transitioner?(:delivered)
    end

    def test_match_transition_behavior
      assert_raises(ArgumentError) { @system.match?({}) }
      assert_raises(ArgumentError) { @system.match?({cart: :submitted, paid: :shipped}) }

      # Valid transitions
      assert @system.match?(cart: [:submitted, :abandoned])
      assert @system.match?(submitted: [:paid, :cancelled])
      assert @system.match?(paid: [:shipped, :refunded])
      assert @system.match?(shipped: [:delivered, :returned])

      # Invalid transitions (to state doesn't exactly match)
      refute @system.match?(cart: :submitted)
      refute @system.match?(paid: :shipped), "Should be false: [:shipped] != [:shipped, :refunded]"
      refute @system.match?(paid: [:shipped])
      refute @system.match?(shipped: :delivered)
      refute @system.match?(shipped: [:delivered])

      # Invalid: from a terminal state
      refute @system.match?(abandoned: :cart)
      refute @system.match?(returned: :shipped)

      # Invalid: to a non-existent state
      refute @system.match?(cart: :processing)
    end

    def test_allows_transition_behavior
      # Tests ArgumentErrors first
      assert_raises(ArgumentError, "transition cannot be empty") do
        @system.allows?({})
      end
      assert_raises(ArgumentError, "transition must contain exactly one key-value pair") do
        @system.allows?({cart: :submitted, paid: :shipped})
      end

      # Test allowed individual transitions
      assert @system.allows?(cart: "submitted")
      assert @system.allows?(cart: :abandoned)
      assert @system.allows?("submitted" => :paid)
      assert @system.allows?(submitted: "cancelled")
      assert @system.allows?("paid" => "shipped")
      assert @system.allows?(paid: :refunded)
      assert @system.allows?("shipped" => "delivered")
      assert @system.allows?(shipped: :returned)

      # Test disallowed transitions
      refute @system.allows?(abandoned: "cart"), "Terminal state cannot transition"
      refute @system.allows?(returned: "shipped"), "Terminal state cannot transition"
      refute @system.allows?(cart: "processing"), "Cannot transition to non-existent state"
      refute @system.allows?(processing: "cart"), "Non-existent state cannot transition"

      # Test transitions that aren't defined in the rules but states exist
      refute @system.allows?(delivered: "returned"), "No such transition defined"
      refute @system.allows?(refunded: "shipped"), "No such transition defined"
    end

    def test_overlaps_transition_behavior
      # Tests ArgumentErrors first
      assert_raises(ArgumentError, "transition cannot be empty") do
        @system.overlaps?({})
      end
      assert_raises(ArgumentError, "transition must contain exactly one key-value pair") do
        @system.overlaps?({cart: :submitted, paid: :shipped})
      end

      # Test basic overlap behavior
      assert @system.overlaps?(cart: [:submitted, :abandoned])
      assert @system.overlaps?(cart: :submitted), "Single to-state should overlap"
      assert @system.overlaps?(paid: [:shipped, :refunded])
      assert @system.overlaps?(paid: :shipped), "Single to-state should overlap"
      assert @system.overlaps?(shipped: [:delivered, :returned])

      # Test with multiple from states and targets
      assert @system.overlaps?([:cart, :submitted] => [:submitted, :paid]), "Multiple valid paths"
      assert @system.overlaps?([:paid, :shipped] => :shipped), "paid can reach shipped"
      assert @system.overlaps?([:cart, :paid] => [:shipped, :abandoned]), "Multiple overlaps"

      # Test no overlap cases
      refute @system.overlaps?(abandoned: "cart"), "Terminal state cannot transition"
      refute @system.overlaps?(returned: "shipped"), "Terminal state cannot transition"
      refute @system.overlaps?(cart: "processing"), "Cannot overlap with non-existent state"
      refute @system.overlaps?(processing: "cart"), "Non-existent from-state cannot overlap"

      # Demonstrate difference from match? - overlaps? is more permissive
      refute @system.match?(paid: :shipped), "match? requires exact rule"
      assert @system.overlaps?(paid: :shipped), "overlaps? allows partial overlap"
    end

    def test_deconstruct_keys
      keys_to_get = [:states, :locked]
      expected_subset = {
        states: ["cart", "submitted", "abandoned", "paid", "cancelled", "shipped", "refunded", "delivered", "returned"],
        locked: true
      }
      assert_equal expected_subset, @system.deconstruct_keys(keys_to_get)
      assert_equal @system.to_h, @system.deconstruct_keys(nil)
    end
  end

  class UserAccountTest < Test
    def setup
      @system = StateJacket::TransitionSystem.new
      @system.add pending: [:active, :rejected]
      @system.add active: [:suspended, :deactivated]
      @system.add suspended: [:active, :deactivated]
      @system.add deactivated: :active
      @system.lock
    end

    def test_to_h
      expected = {
        locked: true,
        states: ["pending", "active", "rejected", "suspended", "deactivated"],
        transitioners: ["pending", "active", "suspended", "deactivated"],
        terminals: ["rejected"],
        rules: {
          "pending" => ["active", "rejected"],
          "active" => ["suspended", "deactivated"],
          "rejected" => nil,
          "suspended" => ["active", "deactivated"],
          "deactivated" => ["active"]
        }
      }
      assert_equal expected, @system.to_h
    end

    def test_states
      expected_states = ["pending", "active", "rejected", "suspended", "deactivated"]
      assert_equal expected_states, @system.states
    end

    def test_transitioners
      expected_transitioners = ["pending", "active", "suspended", "deactivated"]
      assert_equal expected_transitioners, @system.transitioners
    end

    def test_terminals
      expected_terminals = ["rejected"]
      assert_equal expected_terminals, @system.terminals
    end

    def test_locked_status_and_idempotency
      system = StateJacket::TransitionSystem.new
      refute system.locked?, "System should not be locked initially"

      locked_system_ref1 = system.lock
      assert system.locked?, "System should be locked after first call to lock"
      assert_same system, locked_system_ref1, "lock should return self"

      locked_system_ref2 = system.lock
      assert system.locked?, "System should remain locked after second call to lock"
      assert_same system, locked_system_ref2, "lock should return self on subsequent calls (idempotency)"
    end

    def test_state_predicate
      assert @system.include?(:pending)
      assert @system.include?(:deactivated)
      refute @system.include?(:archived)
    end

    def test_terminal_predicate
      assert @system.terminal?(:rejected)
      refute @system.terminal?(:pending)
      refute @system.terminal?(:active)
    end

    def test_transitioner_predicate
      assert @system.transitioner?(:pending)
      assert @system.transitioner?(:active)
      assert @system.transitioner?(:suspended)
      assert @system.transitioner?(:deactivated)
      refute @system.transitioner?(:rejected)
    end

    def test_match_transition_behavior
      assert_raises(ArgumentError) { @system.match?({}) }
      assert_raises(ArgumentError) { @system.match?({pending: :active, active: :suspended}) }

      # Valid transitions
      assert @system.match?(pending: [:active, :rejected])
      assert @system.match?(active: [:suspended, :deactivated])
      assert @system.match?(suspended: [:active, :deactivated])
      assert @system.match?(deactivated: :active)
      assert @system.match?(deactivated: [:active])

      # Invalid transitions (to state doesn't exactly match)
      refute @system.match?(pending: :active)
      refute @system.match?(pending: [:active])
      refute @system.match?(active: :suspended)
      refute @system.match?(active: [:suspended])

      # Invalid: from a terminal state
      refute @system.match?(rejected: :pending)

      # Invalid: to a non-existent state
      refute @system.match?(pending: :archived)
    end

    def test_allows_transition_behavior
      # Tests ArgumentErrors first
      assert_raises(ArgumentError, "transition cannot be empty") do
        @system.allows?({})
      end
      assert_raises(ArgumentError, "transition must contain exactly one key-value pair") do
        @system.allows?({pending: :active, active: :suspended})
      end

      # Test allowed individual transitions
      assert @system.allows?(pending: "active")
      assert @system.allows?(pending: :rejected)
      assert @system.allows?("active" => :suspended)
      assert @system.allows?(active: "deactivated")
      assert @system.allows?("suspended" => "active")
      assert @system.allows?(suspended: :deactivated)
      assert @system.allows?("deactivated" => "active")

      # Test disallowed transitions
      refute @system.allows?(rejected: "pending"), "Terminal state cannot transition"
      refute @system.allows?(pending: "archived"), "Cannot transition to non-existent state"
      refute @system.allows?(archived: "pending"), "Non-existent state cannot transition"

      # Test transitions that aren't defined in the rules but states exist
      refute @system.allows?(active: "rejected"), "No such transition defined"
      refute @system.allows?(suspended: "rejected"), "No such transition defined"
    end

    def test_overlaps_transition_behavior
      # Tests ArgumentErrors first
      assert_raises(ArgumentError, "transition cannot be empty") do
        @system.overlaps?({})
      end
      assert_raises(ArgumentError, "transition must contain exactly one key-value pair") do
        @system.overlaps?({pending: :active, active: :suspended})
      end

      # Test basic overlap behavior
      assert @system.overlaps?(pending: [:active, :rejected])
      assert @system.overlaps?(pending: :active), "Single to-state should overlap"
      assert @system.overlaps?(active: [:suspended, :deactivated])
      assert @system.overlaps?(suspended: [:active, :deactivated])
      assert @system.overlaps?(deactivated: :active)

      # Test with multiple from states - showing the cyclic nature
      assert @system.overlaps?([:active, :suspended] => :deactivated), "Both can reach deactivated"
      assert @system.overlaps?([:suspended, :deactivated] => :active), "Both can reach active"
      assert @system.overlaps?([:pending, :suspended] => [:active, :rejected]), "Multiple overlaps"

      # Test no overlap cases
      refute @system.overlaps?(rejected: "pending"), "Terminal state cannot transition"
      refute @system.overlaps?(pending: "archived"), "Cannot overlap with non-existent state"
      refute @system.overlaps?(archived: "pending"), "Non-existent from-state cannot overlap"

      # Demonstrate difference from match? - overlaps? is more permissive
      refute @system.match?(pending: :active), "match? requires exact rule"
      assert @system.overlaps?(pending: :active), "overlaps? allows partial overlap"
    end

    def test_deconstruct_keys
      keys_to_get = [:rules, :locked]
      expected_subset = {
        rules: {
          "pending" => ["active", "rejected"],
          "active" => ["suspended", "deactivated"],
          "rejected" => nil,
          "suspended" => ["active", "deactivated"],
          "deactivated" => ["active"]
        },
        locked: true
      }
      assert_equal expected_subset, @system.deconstruct_keys(keys_to_get)
      assert_equal @system.to_h, @system.deconstruct_keys(nil)
    end
  end
end
