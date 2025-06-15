# frozen_string_literal: true

require_relative "../../test_helper"

class StateJacket::Matrix::Test < Test
  def setup
    @matrix = StateJacket::Matrix.new
  end

  def test_add_not_permitted_when_locked
    @matrix.add :initial_state
    @matrix.lock
    assert_raises(StateJacket::Matrix::Error, "additions not permitted when locked") do
      @matrix.add :another_state
    end
    assert_raises(StateJacket::Matrix::Error, "additions not permitted when locked") do
      @matrix.add new_state: :target_state
    end
  end

  def test_add_empty_hash_raises_argument_error
    assert_raises(StateJacket::Matrix::Error, "transition cannot be empty") do
      @matrix.add({})
    end
  end

  def test_add_hash_with_multiple_pairs_raises_argument_error
    assert_raises(StateJacket::Matrix::Error, "transition must contain exactly one key-value pair") do
      @matrix.add({state_one: :target_one, state_two: :target_two})
    end
  end

  def test_add_with_nil_transition_key_raises_error
    assert_raises(StateJacket::Matrix::Error, "missing transition key") do
      @matrix.add nil => :some_target
    end
  end

  def test_add_with_empty_array_transition_key_raises_error
    assert_raises(StateJacket::Matrix::Error, "missing transition key") do
      @matrix.add [] => :some_target
    end
  end

  def test_add_with_array_containing_nil_transition_key_raises_error
    assert_raises(StateJacket::Matrix::Error, "nil transition key") do
      @matrix.add [:state_a, nil, :state_b] => :some_target
    end
  end

  def test_add_with_symbol_and_string_keys_and_values_are_normalized
    @matrix.add symbol_from: "string_to"
    @matrix.add "string_from_too" => :symbol_to_too
    @matrix.add "another_from" => ["string_target", :symbol_target]

    # Test that all states were added correctly
    expected_states = ["symbol_from", "string_to", "string_from_too", "symbol_to_too", "another_from", "string_target", "symbol_target"]
    assert_equal expected_states.sort, @matrix.states.sort

    # Test transitioners and terminals
    expected_transitioners = ["symbol_from", "string_from_too", "another_from"]
    expected_terminals = ["string_to", "symbol_to_too", "string_target", "symbol_target"]
    assert_equal expected_transitioners.sort, @matrix.transitioners.sort
    assert_equal expected_terminals.sort, @matrix.terminals.sort

    # Test allowed transitions
    assert @matrix.allows?("symbol_from" => "string_to")
    assert @matrix.allows?("string_from_too" => "symbol_to_too")
    assert @matrix.allows?("another_from" => "string_target")
    assert @matrix.allows?("another_from" => "symbol_target")
  end

  def test_add_ensures_all_to_states_are_initialized_as_terminals_if_not_defined
    @matrix.add state_a: [:state_b, :state_c]

    # Target states should be automatically added as terminals
    assert @matrix.include?("state_b")
    assert @matrix.terminal?("state_b")
    assert @matrix.include?("state_c")
    assert @matrix.terminal?("state_c")

    # Add a transition where one of the 'to' states already exists as a transitioner
    @matrix.add state_b: :state_d # state_b becomes a transitioner

    assert @matrix.transitioner?("state_b")
    assert @matrix.terminal?("state_d")

    @matrix.add state_e: [:state_b, :state_f] # state_b is already a transitioner

    # Verify final state structure through public API
    expected_states = ["state_a", "state_b", "state_c", "state_d", "state_e", "state_f"]
    expected_transitioners = ["state_a", "state_b", "state_e"]
    expected_terminals = ["state_c", "state_d", "state_f"]

    assert_equal expected_states.sort, @matrix.states.sort
    assert_equal expected_transitioners.sort, @matrix.transitioners.sort
    assert_equal expected_terminals.sort, @matrix.terminals.sort

    # Test allowed transitions
    assert @matrix.allows?("state_a" => "state_b")
    assert @matrix.allows?("state_a" => "state_c")
    assert @matrix.allows?("state_b" => "state_d")
    assert @matrix.allows?("state_e" => "state_b")
    assert @matrix.allows?("state_e" => "state_f")
  end

  class ApprovalsTest < Test
    def setup
      @matrix = StateJacket::Matrix.new
    end

    def test_add_single_transition_multiple_targets
      @matrix.add pending: [:approved, :rejected]

      assert_equal ["pending", "approved", "rejected"].sort, @matrix.states.sort
      assert_equal ["pending"], @matrix.transitioners
      assert_equal ["approved", "rejected"].sort, @matrix.terminals.sort

      # Test allowed transitions
      assert @matrix.allows?("pending" => "approved")
      assert @matrix.allows?("pending" => "rejected")

      # Test disallowed transitions
      refute @matrix.allows?("approved" => "pending")
      refute @matrix.allows?("rejected" => "pending")
    end

    def test_add_non_hash_creates_terminal
      @matrix.add :pending
      @matrix.add :approved
      @matrix.add :rejected

      assert_equal ["pending", "approved", "rejected"].sort, @matrix.states.sort
      assert_equal [], @matrix.transitioners
      assert_equal ["approved", "pending", "rejected"].sort, @matrix.terminals.sort

      # All should be terminal states
      assert @matrix.terminal?("pending")
      assert @matrix.terminal?("approved")
      assert @matrix.terminal?("rejected")
    end

    def test_add_to_existing_terminal_makes_it_transitioner
      @matrix.add :pending # terminal
      assert @matrix.terminal?("pending")

      @matrix.add pending: :approved # now transitioner

      assert_equal ["pending", "approved"].sort, @matrix.states.sort
      assert_equal ["pending"], @matrix.transitioners
      assert_equal ["approved"], @matrix.terminals

      assert @matrix.transitioner?("pending")
      assert @matrix.terminal?("approved")
      assert @matrix.allows?("pending" => "approved")
    end

    def test_add_to_existing_transitioner_concatenates_targets
      @matrix.add pending: :approved
      @matrix.add pending: :rejected # Add another target

      assert_equal ["pending", "approved", "rejected"].sort, @matrix.states.sort
      assert_equal ["pending"], @matrix.transitioners
      assert_equal ["approved", "rejected"].sort, @matrix.terminals.sort

      # Test that both transitions are allowed
      assert @matrix.allows?("pending" => "approved")
      assert @matrix.allows?("pending" => "rejected")
    end

    def test_add_nil_target_to_new_state_makes_it_terminal
      @matrix.add pending: nil

      assert @matrix.include?("pending")
      assert @matrix.terminal?("pending")
      refute @matrix.transitioner?("pending")

      assert_equal ["pending"], @matrix.states
      assert_equal [], @matrix.transitioners
      assert_equal ["pending"], @matrix.terminals
    end

    def test_add_nil_target_to_existing_transitioner_makes_it_terminal
      @matrix.add pending: :approved
      assert @matrix.transitioner?("pending")

      @matrix.add pending: nil # Makes existing transitioner terminal

      assert @matrix.terminal?("pending")
      refute @matrix.transitioner?("pending")

      assert_equal ["pending", "approved"].sort, @matrix.states.sort
      assert_equal [], @matrix.transitioners
      assert_equal ["pending", "approved"].sort, @matrix.terminals.sort
    end
  end

  class RailwayTest < Test
    def setup
      @matrix = StateJacket::Matrix.new
    end

    def test_build_railway_system
      @matrix.add station_a: [:station_b, :station_c]
      @matrix.add station_b: :station_c

      assert_equal ["station_a", "station_b", "station_c"].sort, @matrix.states.sort
      assert_equal ["station_a", "station_b"].sort, @matrix.transitioners.sort
      assert_equal ["station_c"], @matrix.terminals

      # Test allowed transitions
      assert @matrix.allows?("station_a" => "station_b")
      assert @matrix.allows?("station_a" => "station_c")
      assert @matrix.allows?("station_b" => "station_c")

      # Test disallowed transitions
      refute @matrix.allows?("station_c" => "station_a")
      refute @matrix.allows?("station_c" => "station_b")
    end

    def test_add_multiple_from_states_to_single_target
      @matrix.add [:station_x, :station_y] => :station_z

      assert_equal ["station_x", "station_y", "station_z"].sort, @matrix.states.sort
      assert_equal ["station_x", "station_y"].sort, @matrix.transitioners.sort
      assert_equal ["station_z"], @matrix.terminals.sort

      # Test allowed transitions
      assert @matrix.allows?("station_x" => "station_z")
      assert @matrix.allows?("station_y" => "station_z")

      # Test disallowed transitions
      refute @matrix.allows?("station_z" => "station_x")
      refute @matrix.allows?("station_z" => "station_y")
    end
  end

  class AddEcommerceTest < Test
    def setup
      @matrix = StateJacket::Matrix.new
    end

    def test_build_ecommerce_system_incrementally
      @matrix.add cart: [:submitted, :abandoned]

      # After first step
      assert_equal ["cart", "submitted", "abandoned"].sort, @matrix.states.sort
      assert_equal ["cart"], @matrix.transitioners
      assert_equal ["submitted", "abandoned"].sort, @matrix.terminals.sort

      @matrix.add submitted: [:paid, :cancelled]

      # After second step
      assert_equal ["cart", "submitted", "abandoned", "paid", "cancelled"].sort, @matrix.states.sort
      assert_equal ["cart", "submitted"].sort, @matrix.transitioners.sort
      assert_equal ["abandoned", "paid", "cancelled"].sort, @matrix.terminals.sort

      @matrix.add paid: :shipped
      @matrix.add shipped: :delivered

      # Final state
      expected_states = ["cart", "submitted", "abandoned", "paid", "cancelled", "shipped", "delivered"]
      expected_transitioners = ["cart", "submitted", "paid", "shipped"]
      expected_terminals = ["abandoned", "cancelled", "delivered"]

      assert_equal expected_states.sort, @matrix.states.sort
      assert_equal expected_transitioners.sort, @matrix.transitioners.sort
      assert_equal expected_terminals.sort, @matrix.terminals.sort

      # Test allowed transition path
      assert @matrix.allows?("cart" => "submitted")
      assert @matrix.allows?("submitted" => "paid")
      assert @matrix.allows?("paid" => "shipped")
      assert @matrix.allows?("shipped" => "delivered")
    end
  end

  class OrderProcessorTest < Test
    def setup
      @matrix = StateJacket::Matrix.new
    end

    def test_build_order_processor_system
      @matrix.add cart: [:submitted, :abandoned]
      @matrix.add submitted: [:paid, :cancelled]
      @matrix.add paid: [:shipped, :refunded]
      @matrix.add shipped: [:delivered, :returned]

      expected_states = ["cart", "submitted", "abandoned", "paid", "cancelled", "shipped", "refunded", "delivered", "returned"]
      expected_transitioners = ["cart", "submitted", "paid", "shipped"]
      expected_terminals = ["abandoned", "cancelled", "refunded", "delivered", "returned"]

      assert_equal expected_states.sort, @matrix.states.sort
      assert_equal expected_transitioners.sort, @matrix.transitioners.sort
      assert_equal expected_terminals.sort, @matrix.terminals.sort

      # Test allowed transition paths
      assert @matrix.allows?("cart" => "submitted")
      assert @matrix.allows?("cart" => "abandoned")
      assert @matrix.allows?("submitted" => "paid")
      assert @matrix.allows?("submitted" => "cancelled")
      assert @matrix.allows?("paid" => "shipped")
      assert @matrix.allows?("paid" => "refunded")
      assert @matrix.allows?("shipped" => "delivered")
      assert @matrix.allows?("shipped" => "returned")
    end
  end

  class UserAccountTest < Test
    def setup
      @matrix = StateJacket::Matrix.new
    end

    def test_build_user_account_system
      @matrix.add pending: [:active, :rejected]
      @matrix.add active: [:suspended, :deactivated]
      @matrix.add suspended: [:active, :deactivated]
      @matrix.add deactivated: :active # Loops back

      expected_states = ["pending", "active", "rejected", "suspended", "deactivated"]
      expected_transitioners = ["pending", "active", "suspended", "deactivated"]
      expected_terminals = ["rejected"]

      assert_equal expected_states.sort, @matrix.states.sort
      assert_equal expected_transitioners.sort, @matrix.transitioners.sort
      assert_equal expected_terminals.sort, @matrix.terminals.sort

      # Test allowed transitions including the loop
      assert @matrix.allows?("pending" => "active")
      assert @matrix.allows?("pending" => "rejected")
      assert @matrix.allows?("active" => "suspended")
      assert @matrix.allows?("active" => "deactivated")
      assert @matrix.allows?("suspended" => "active")
      assert @matrix.allows?("suspended" => "deactivated")
      assert @matrix.allows?("deactivated" => "active") # Loop back

      # Test terminal state behavior
      refute @matrix.allows?("rejected" => "active")
    end
  end
end
