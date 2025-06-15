# frozen_string_literal: true

require_relative "../test_helper"

class StateJacket::PatternMatchingTest < Test
  class MachineStateMatchingTest < Test
    def setup
      system = StateJacket::Matrix.new
      system.add cart: [:submitted, :abandoned]
      system.add submitted: [:paid, :cancelled]
      system.add paid: [:shipped, :refunded]
      system.add shipped: [:delivered, :returned]

      @machine = StateJacket::Machine.new(system, current_state: :cart)
      @machine.on :submit, cart: :submitted
      @machine.on :abandon, cart: :abandoned
      @machine.on :pay, submitted: :paid
      @machine.on :cancel, submitted: :cancelled
      @machine.on :ship, paid: :shipped
      @machine.on :refund, paid: :refunded
      @machine.on :deliver, shipped: :delivered
      @machine.on :return, shipped: :returned
      @machine.lock
    end

    def test_machine_state_pattern_matching
      # Test pattern matching on machine state as described in README
      result = handle_order_state(@machine)
      assert_equal "Order is in cart state", result

      @machine.trigger(:submit)
      result = handle_order_state(@machine)
      assert_equal "Order has been submitted", result

      @machine.trigger(:pay)
      result = handle_order_state(@machine)
      assert_equal "Order has been paid", result

      @machine.trigger(:ship)
      result = handle_order_state(@machine)
      assert_equal "Order has been shipped", result

      @machine.trigger(:deliver)
      result = handle_order_state(@machine)
      assert_equal "Order has been delivered", result
    end

    def test_machine_pattern_matching_with_additional_attributes
      # Testing with additional attributes beyond current_state
      cart_machine = @machine

      submitted_machine = StateJacket::Machine.new(@machine.matrix, current_state: :submitted)
      submitted_machine.on :pay, submitted: :paid
      submitted_machine.on :cancel, submitted: :cancelled
      submitted_machine.lock

      shipped_machine = StateJacket::Machine.new(@machine.matrix, current_state: :shipped)
      shipped_machine.on :deliver, shipped: :delivered
      shipped_machine.on :return, shipped: :returned
      shipped_machine.lock

      # Testing matching on current_state and finished status
      result = case cart_machine
      in {current_state: "cart", finished: false}
        "Cart is active"
      else
        "Something else"
      end
      assert_equal "Cart is active", result

      # Testing matching on current_state and triggerable_events
      result = case submitted_machine
      in {current_state: "submitted", triggerable_events: events} if events.include?("pay")
        "Can be paid"
      else
        "Cannot be paid"
      end
      assert_equal "Can be paid", result

      # Testing matching on current_state and reachable_states
      result = case shipped_machine
      in {current_state: "shipped", reachable_states: states} if states.include?("delivered")
        "Can be delivered"
      else
        "Cannot be delivered"
      end
      assert_equal "Can be delivered", result
    end

    private

    # Implementation of handle_order_state from README example
    def handle_order_state(machine)
      case machine
      in current_state: "cart" then "Order is in cart state"
      in current_state: "submitted" then "Order has been submitted"
      in current_state: "paid" then "Order has been paid"
      in current_state: "shipped" then "Order has been shipped"
      in current_state: "delivered" then "Order has been delivered"
      else "Unknown order state"
      end
    end
  end

  class TransitionMatchingTest < Test
    def setup
      system = StateJacket::Matrix.new
      system.add cart: [:submitted, :abandoned]
      system.add submitted: [:paid, :cancelled]

      @machine = StateJacket::Machine.new(system, current_state: :cart)
      @machine.on :submit, cart: :submitted
      @machine.on :abandon, cart: :abandoned
      @machine.on :pay, submitted: :paid
      @machine.on :cancel, submitted: :cancelled
      @machine.lock
    end

    def test_transition_pattern_matching
      # Test successful transition
      result = @machine.trigger(:submit)
      handled_result = handle_order_transition(result)
      assert_equal "Order submitted successfully", handled_result

      # Test unsuccessful transition
      # Create a transition that will fail by raising an error in the block
      begin
        result = @machine.trigger(:pay) { |from, to|
          raise "Payment processing failed"
        }
      rescue => e
        # This should not happen as the error should be caught by the state machine
        flunk "Error should be captured by the state machine: #{e.message}"
      end

      handled_result = handle_order_transition(result)
      assert_equal "Error during payment: Payment processing failed", handled_result
    end

    def test_transition_pattern_matching_with_specifics
      # Test pattern matching with specific attributes
      result = @machine.trigger(:submit)

      # Test matching on specific event
      outcome = case result
      in {event: "submit", status: :ok}
        "Submitted OK"
      else
        "Other event"
      end
      assert_equal "Submitted OK", outcome

      # Test matching on from/to states
      outcome = case result
      in {from: "cart", to: "submitted"}
        "From cart to submitted"
      else
        "Other transition"
      end
      assert_equal "From cart to submitted", outcome

      # Test matching with error handling
      @machine.trigger(:pay) { raise "Error message" }

      error_result = @machine.trigger(:pay) { raise "Test error" }
      outcome = case error_result
      in {status: :error, error: error}
        "Error: #{error.message}"
      else
        "No error"
      end
      assert_equal "Error: Test error", outcome
    end

    private

    # Implementation of handle_order_transition from README example
    def handle_order_transition(result)
      case result
      in event: "submit", status: :ok then "Order submitted successfully"
      in event: "pay", status: :ok then "Payment processed successfully"
      in event: "pay", status: :error, error: then "Error during payment: #{error.message}"
      in status: :error, error: then "Error: #{error.message}"
      else "Unknown transition"
      end
    end
  end

  class PatternMatchingWithGuardClausesTest < Test
    def setup
      system = StateJacket::Matrix.new
      system.add pending: [:active, :locked]
      system.add active: [:locked, :suspended]
      system.add locked: [:active, :suspended]
      system.add suspended: [:active, :locked]

      @user_machine = StateJacket::Machine.new(system, current_state: :pending)
      @user_machine.on :activate, pending: :active
      @user_machine.on :lock, [:pending, :active, :suspended] => :locked
      @user_machine.on :suspend, [:active, :locked] => :suspended
      @user_machine.on :reactivate, [:locked, :suspended] => :active
      @user_machine.lock
    end

    def test_pattern_matching_with_guard_clauses
      # Test with pending user
      permissions = determine_user_permissions(@user_machine, admin: false)
      assert_equal "View only", permissions

      # Test with active user
      @user_machine.trigger(:activate)
      permissions = determine_user_permissions(@user_machine, admin: false)
      assert_equal "Edit and view", permissions

      # Test with active admin user
      permissions = determine_user_permissions(@user_machine, admin: true)
      assert_equal "Full access", permissions

      # Test with locked user
      @user_machine.trigger(:lock)
      permissions = determine_user_permissions(@user_machine, admin: false)
      assert_equal "No access", permissions

      # Test with locked admin
      permissions = determine_user_permissions(@user_machine, admin: true)
      assert_equal "View only", permissions

      # Test with suspended user
      @user_machine.trigger(:suspend)
      permissions = determine_user_permissions(@user_machine, admin: false)
      assert_equal "No access", permissions
    end

    private

    # Implementation of determine_user_permissions from README example
    def determine_user_permissions(machine, admin:)
      case machine
      in current_state: "active" if admin then "Full access"
      in current_state: "active" then "Edit and view"
      in current_state: "pending" if admin then "View only"
      in current_state: "locked" if admin then "View only"
      in current_state: "pending" then "View only"
      else "No access"
      end
    end
  end

  class BuiltInPatternClassesTest < Test
    def setup
      @system = StateJacket::Matrix.new
      @system.add draft: [:submitted, :abandoned]
      @system.add submitted: [:approved, :rejected]
      @system.add approved: [:published, :archived]
      @system.lock

      @machine = StateJacket::Machine.new(@system, current_state: :draft)
      @machine.on :submit, draft: :submitted
      @machine.on :abandon, draft: :abandoned
      @machine.on :approve, submitted: :approved
      @machine.on :reject, submitted: :rejected
      @machine.on :publish, approved: :published
      @machine.on :archive, approved: :archived
      @machine.lock
    end

    def test_transition_matching_in_compound_patterns
      # Let's test pattern matching with compound patterns
      result = @machine.trigger(:submit)

      # Using | (or) pattern
      status = case result
      in {status: :ok} | {status: :success}
        "successful"
      in {status: :error} | {status: :failure}
        "failed"
      else
        "unknown"
      end
      assert_equal "successful", status

      # Using alternative destructuring approaches
      @machine.trigger(:approve) { raise "Cannot approve" }

      # Test destructuring in different ways
      # This is similar to what the README describes as "Built-in Pattern Classes"
      extracted = case result
      in {event:, from:, to:, status:} # Implicit hash destructuring
        {event: event, from: from, to: to, status: status}
      else
        {}
      end

      assert_equal({
        event: "submit",
        from: "draft",
        to: "submitted",
        status: :ok
      }, extracted)
    end

    def test_matrix_pattern_matching
      # Test pattern matching on the matrix
      result = case @system
      in {transitioners: trans, terminals: _terms} if trans.include?("draft")
        "Draft is a transitioner"
      else
        "Draft is not a transitioner"
      end
      assert_equal "Draft is a transitioner", result

      # Match against states
      result = case @system
      in {states: states} if states.include?("published")
        "Published is a state"
      else
        "Published is not a state"
      end
      assert_equal "Published is a state", result

      # Match against rules
      result = case @system
      in {rules: rules} if rules["draft"]&.include?("submitted")
        "Draft can transition to submitted"
      else
        "Draft cannot transition to submitted"
      end
      assert_equal "Draft can transition to submitted", result
    end
  end
end
