# frozen_string_literal: true

require_relative "../../test_helper"

class StateJacket::TransitionSystem::Test < Test
  def setup
    @system = StateJacket::TransitionSystem.new
  end

  def test_add_not_permitted_when_locked
    @system.add :initial_state
    @system.lock
    assert_raises(ArgumentError, "additions not permitted when locked") do
      @system.add :another_state
    end
    assert_raises(ArgumentError, "additions not permitted when locked") do
      @system.add new_state: :target_state
    end
  end

  def test_add_empty_hash_raises_argument_error
    assert_raises(ArgumentError, "transition cannot be empty") do
      @system.add({})
    end
  end

  def test_add_hash_with_multiple_pairs_raises_argument_error
    assert_raises(ArgumentError, "transition must contain exactly one key-value pair") do
      @system.add({state_one: :target_one, state_two: :target_two})
    end
  end

  def test_add_with_nil_transition_key_raises_error
    assert_raises(ArgumentError, "missing transition key") do
      @system.add nil => :some_target
    end
  end

  def test_add_with_empty_array_transition_key_raises_error
    assert_raises(ArgumentError, "missing transition key") do
      @system.add [] => :some_target
    end
  end

  def test_add_with_array_containing_nil_transition_key_raises_error
    assert_raises(ArgumentError, "nil transition key") do
      @system.add [:state_a, nil, :state_b] => :some_target
    end
  end

  def test_add_with_symbol_and_string_keys_and_values_are_normalized
    @system.add symbol_from: "string_to"
    @system.add "string_from_too" => :symbol_to_too
    @system.add "another_from" => ["string_target", :symbol_target]

    # Test that all states were added correctly
    expected_states = ["symbol_from", "string_to", "string_from_too", "symbol_to_too", "another_from", "string_target", "symbol_target"]
    assert_equal expected_states.sort, @system.states.sort

    # Test transitioners and terminals
    expected_transitioners = ["symbol_from", "string_from_too", "another_from"]
    expected_terminals = ["string_to", "symbol_to_too", "string_target", "symbol_target"]
    assert_equal expected_transitioners.sort, @system.transitioners.sort
    assert_equal expected_terminals.sort, @system.terminals.sort

    # Test allowed transitions
    assert @system.allows?("symbol_from" => "string_to")
    assert @system.allows?("string_from_too" => "symbol_to_too")
    assert @system.allows?("another_from" => "string_target")
    assert @system.allows?("another_from" => "symbol_target")
  end

  def test_add_ensures_all_to_states_are_initialized_as_terminals_if_not_defined
    @system.add state_a: [:state_b, :state_c]

    # Target states should be automatically added as terminals
    assert @system.include?("state_b")
    assert @system.terminal?("state_b")
    assert @system.include?("state_c")
    assert @system.terminal?("state_c")

    # Add a transition where one of the 'to' states already exists as a transitioner
    @system.add state_b: :state_d # state_b becomes a transitioner

    assert @system.transitioner?("state_b")
    assert @system.terminal?("state_d")

    @system.add state_e: [:state_b, :state_f] # state_b is already a transitioner

    # Verify final state structure through public API
    expected_states = ["state_a", "state_b", "state_c", "state_d", "state_e", "state_f"]
    expected_transitioners = ["state_a", "state_b", "state_e"]
    expected_terminals = ["state_c", "state_d", "state_f"]

    assert_equal expected_states.sort, @system.states.sort
    assert_equal expected_transitioners.sort, @system.transitioners.sort
    assert_equal expected_terminals.sort, @system.terminals.sort

    # Test allowed transitions
    assert @system.allows?("state_a" => "state_b")
    assert @system.allows?("state_a" => "state_c")
    assert @system.allows?("state_b" => "state_d")
    assert @system.allows?("state_e" => "state_b")
    assert @system.allows?("state_e" => "state_f")
  end

  class ApprovalsTest < Test
    def setup
      @system = StateJacket::TransitionSystem.new
    end

    def test_add_single_transition_multiple_targets
      @system.add pending: [:approved, :rejected]

      assert_equal ["pending", "approved", "rejected"].sort, @system.states.sort
      assert_equal ["pending"], @system.transitioners
      assert_equal ["approved", "rejected"].sort, @system.terminals.sort

      # Test allowed transitions
      assert @system.allows?("pending" => "approved")
      assert @system.allows?("pending" => "rejected")

      # Test disallowed transitions
      refute @system.allows?("approved" => "pending")
      refute @system.allows?("rejected" => "pending")
    end

    def test_add_non_hash_creates_terminal
      @system.add :pending
      @system.add :approved
      @system.add :rejected

      assert_equal ["pending", "approved", "rejected"].sort, @system.states.sort
      assert_equal [], @system.transitioners
      assert_equal ["approved", "pending", "rejected"].sort, @system.terminals.sort

      # All should be terminal states
      assert @system.terminal?("pending")
      assert @system.terminal?("approved")
      assert @system.terminal?("rejected")
    end

    def test_add_to_existing_terminal_makes_it_transitioner
      @system.add :pending # terminal
      assert @system.terminal?("pending")

      @system.add pending: :approved # now transitioner

      assert_equal ["pending", "approved"].sort, @system.states.sort
      assert_equal ["pending"], @system.transitioners
      assert_equal ["approved"], @system.terminals

      assert @system.transitioner?("pending")
      assert @system.terminal?("approved")
      assert @system.allows?("pending" => "approved")
    end

    def test_add_to_existing_transitioner_concatenates_targets
      @system.add pending: :approved
      @system.add pending: :rejected # Add another target

      assert_equal ["pending", "approved", "rejected"].sort, @system.states.sort
      assert_equal ["pending"], @system.transitioners
      assert_equal ["approved", "rejected"].sort, @system.terminals.sort

      # Test that both transitions are allowed
      assert @system.allows?("pending" => "approved")
      assert @system.allows?("pending" => "rejected")
    end

    def test_add_nil_target_to_new_state_makes_it_terminal
      @system.add pending: nil

      assert @system.include?("pending")
      assert @system.terminal?("pending")
      refute @system.transitioner?("pending")

      assert_equal ["pending"], @system.states
      assert_equal [], @system.transitioners
      assert_equal ["pending"], @system.terminals
    end

    def test_add_nil_target_to_existing_transitioner_makes_it_terminal
      @system.add pending: :approved
      assert @system.transitioner?("pending")

      @system.add pending: nil # Makes existing transitioner terminal

      assert @system.terminal?("pending")
      refute @system.transitioner?("pending")

      assert_equal ["pending", "approved"].sort, @system.states.sort
      assert_equal [], @system.transitioners
      assert_equal ["pending", "approved"].sort, @system.terminals.sort
    end
  end

  class RailwayTest < Test
    def setup
      @system = StateJacket::TransitionSystem.new
    end

    def test_build_railway_system
      @system.add station_a: [:station_b, :station_c]
      @system.add station_b: :station_c

      assert_equal ["station_a", "station_b", "station_c"].sort, @system.states.sort
      assert_equal ["station_a", "station_b"].sort, @system.transitioners.sort
      assert_equal ["station_c"], @system.terminals

      # Test allowed transitions
      assert @system.allows?("station_a" => "station_b")
      assert @system.allows?("station_a" => "station_c")
      assert @system.allows?("station_b" => "station_c")

      # Test disallowed transitions
      refute @system.allows?("station_c" => "station_a")
      refute @system.allows?("station_c" => "station_b")
    end

    def test_add_multiple_from_states_to_single_target
      @system.add [:station_x, :station_y] => :station_z

      assert_equal ["station_x", "station_y", "station_z"].sort, @system.states.sort
      assert_equal ["station_x", "station_y"].sort, @system.transitioners.sort
      assert_equal ["station_z"], @system.terminals.sort

      # Test allowed transitions
      assert @system.allows?("station_x" => "station_z")
      assert @system.allows?("station_y" => "station_z")

      # Test disallowed transitions
      refute @system.allows?("station_z" => "station_x")
      refute @system.allows?("station_z" => "station_y")
    end
  end

  class AddEcommerceTest < Test
    def setup
      @system = StateJacket::TransitionSystem.new
    end

    def test_build_ecommerce_system_incrementally
      @system.add cart: [:submitted, :abandoned]

      # After first step
      assert_equal ["cart", "submitted", "abandoned"].sort, @system.states.sort
      assert_equal ["cart"], @system.transitioners
      assert_equal ["submitted", "abandoned"].sort, @system.terminals.sort

      @system.add submitted: [:paid, :cancelled]

      # After second step
      assert_equal ["cart", "submitted", "abandoned", "paid", "cancelled"].sort, @system.states.sort
      assert_equal ["cart", "submitted"].sort, @system.transitioners.sort
      assert_equal ["abandoned", "paid", "cancelled"].sort, @system.terminals.sort

      @system.add paid: :shipped
      @system.add shipped: :delivered

      # Final state
      expected_states = ["cart", "submitted", "abandoned", "paid", "cancelled", "shipped", "delivered"]
      expected_transitioners = ["cart", "submitted", "paid", "shipped"]
      expected_terminals = ["abandoned", "cancelled", "delivered"]

      assert_equal expected_states.sort, @system.states.sort
      assert_equal expected_transitioners.sort, @system.transitioners.sort
      assert_equal expected_terminals.sort, @system.terminals.sort

      # Test allowed transition path
      assert @system.allows?("cart" => "submitted")
      assert @system.allows?("submitted" => "paid")
      assert @system.allows?("paid" => "shipped")
      assert @system.allows?("shipped" => "delivered")
    end
  end

  class OrderProcessorTest < Test
    def setup
      @system = StateJacket::TransitionSystem.new
    end

    def test_build_order_processor_system
      @system.add cart: [:submitted, :abandoned]
      @system.add submitted: [:paid, :cancelled]
      @system.add paid: [:shipped, :refunded]
      @system.add shipped: [:delivered, :returned]

      expected_states = ["cart", "submitted", "abandoned", "paid", "cancelled", "shipped", "refunded", "delivered", "returned"]
      expected_transitioners = ["cart", "submitted", "paid", "shipped"]
      expected_terminals = ["abandoned", "cancelled", "refunded", "delivered", "returned"]

      assert_equal expected_states.sort, @system.states.sort
      assert_equal expected_transitioners.sort, @system.transitioners.sort
      assert_equal expected_terminals.sort, @system.terminals.sort

      # Test allowed transition paths
      assert @system.allows?("cart" => "submitted")
      assert @system.allows?("cart" => "abandoned")
      assert @system.allows?("submitted" => "paid")
      assert @system.allows?("submitted" => "cancelled")
      assert @system.allows?("paid" => "shipped")
      assert @system.allows?("paid" => "refunded")
      assert @system.allows?("shipped" => "delivered")
      assert @system.allows?("shipped" => "returned")
    end
  end

  class UserAccountTest < Test
    def setup
      @system = StateJacket::TransitionSystem.new
    end

    def test_build_user_account_system
      @system.add pending: [:active, :rejected]
      @system.add active: [:suspended, :deactivated]
      @system.add suspended: [:active, :deactivated]
      @system.add deactivated: :active # Loops back

      expected_states = ["pending", "active", "rejected", "suspended", "deactivated"]
      expected_transitioners = ["pending", "active", "suspended", "deactivated"]
      expected_terminals = ["rejected"]

      assert_equal expected_states.sort, @system.states.sort
      assert_equal expected_transitioners.sort, @system.transitioners.sort
      assert_equal expected_terminals.sort, @system.terminals.sort

      # Test allowed transitions including the loop
      assert @system.allows?("pending" => "active")
      assert @system.allows?("pending" => "rejected")
      assert @system.allows?("active" => "suspended")
      assert @system.allows?("active" => "deactivated")
      assert @system.allows?("suspended" => "active")
      assert @system.allows?("suspended" => "deactivated")
      assert @system.allows?("deactivated" => "active") # Loop back

      # Test terminal state behavior
      refute @system.allows?("rejected" => "active")
    end
  end
end
