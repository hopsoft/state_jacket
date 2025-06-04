# frozen_string_literal: true

require_relative "../../test_helper"

class StateJacket::StateMachine::IntrospectionTest < Test
  class ApprovalsTest < Test
    def setup
      system = StateJacket::TransitionSystem.new
      system.add pending: [:approved, :rejected]

      @machine = StateJacket::StateMachine.new(system, current_state: :pending)
      @machine.on :approve, pending: :approved
      @machine.on :reject, pending: :rejected
      @machine.lock
    end

    def test_to_h
      expected = {
        locked: true,
        current_state: "pending",
        finished: false,
        reachable_states: [
          "approved",
          "rejected"
        ],
        triggerable_events: [
          "approve",
          "reject"
        ],
        rules: {
          "approve" => [
            {
              "pending" => "approved"
            }
          ],
          "reject" => [
            {
              "pending" => "rejected"
            }
          ]
        }
      }

      assert_equal expected, @machine.to_h
    end

    def test_current_state
      assert_equal "pending", @machine.current_state
    end

    def test_events
      assert_equal ["approve", "reject"], @machine.events
    end

    def test_rules
      expected_rules = {
        "approve" => [
          {
            "pending" => "approved"
          }
        ],
        "reject" => [
          {
            "pending" => "rejected"
          }
        ]
      }
      assert_equal expected_rules, @machine.rules
    end

    def test_states
      assert_equal ["pending", "approved", "rejected"], @machine.states
    end

    def test_triggerable_events
      assert_equal ["approve", "reject"], @machine.triggerable_events

      # Trigger an event to change state
      @machine.trigger("approve")
      assert_equal [], @machine.triggerable_events # No events from approved state
    end

    def test_reachable_states
      assert_equal ["approved", "rejected"], @machine.reachable_states

      # Trigger an event to change state
      @machine.trigger("approve")
      assert_equal [], @machine.reachable_states # No reachable states from approved (terminal)
    end

    def test_finished
      refute @machine.finished?, "Should not be finished in 'pending' state"

      # Trigger to terminal state
      @machine.trigger("approve")
      assert @machine.finished?, "Should be finished in 'approved' state"
    end

    def test_locked
      machine = StateJacket::StateMachine.new(@machine.transition_system, current_state: :pending)
      machine.on :approve, pending: :approved

      refute machine.locked?, "Machine should not be locked initially"

      machine.lock
      assert machine.locked?, "Machine should be locked after calling lock"

      # Test idempotence
      machine.lock
      assert machine.locked?, "Machine should remain locked after second lock call"
    end

    def test_include
      assert @machine.include?("approve")
      assert @machine.include?(:reject)
      refute @machine.include?("invalid_event")
    end

    def test_can_trigger
      assert @machine.can_trigger?("approve")
      assert @machine.can_trigger?(:reject)
      refute @machine.can_trigger?("invalid_event")

      # After transition, original events can't be triggered
      @machine.trigger("approve")
      refute @machine.can_trigger?("approve")
      refute @machine.can_trigger?("reject")
    end

    def test_deconstruct_keys
      expected_subset = {
        current_state: "pending",
        finished: false
      }
      assert_equal expected_subset, @machine.deconstruct_keys([:current_state, :finished])

      # With nil or empty, should return full hash
      assert_equal @machine.to_h, @machine.deconstruct_keys(nil)
      assert_equal @machine.to_h, @machine.deconstruct_keys([])
    end
  end

  class RailwayTest < Test
    def setup
      system = StateJacket::TransitionSystem.new
      system.add station_a: [:station_b, :station_c]
      system.add station_b: :station_c

      @machine = StateJacket::StateMachine.new(system, current_state: :station_a)
      @machine.on :route_1, station_a: :station_b
      @machine.on :route_2, station_a: :station_c
      @machine.on :route_3, station_b: :station_c
      @machine.lock
    end

    def test_to_h
      expected = {
        locked: true,
        current_state: "station_a",
        finished: false,
        reachable_states: [
          "station_b",
          "station_c"
        ],
        triggerable_events: [
          "route_1",
          "route_2"
        ],
        rules: {
          "route_1" => [
            {
              "station_a" => "station_b"
            }
          ],
          "route_2" => [
            {
              "station_a" => "station_c"
            }
          ],
          "route_3" => [
            {
              "station_b" => "station_c"
            }
          ]
        }
      }

      assert_equal expected, @machine.to_h
    end

    def test_current_state
      assert_equal "station_a", @machine.current_state

      @machine.trigger("route_1")
      assert_equal "station_b", @machine.current_state

      @machine.trigger("route_3")
      assert_equal "station_c", @machine.current_state
    end

    def test_events
      assert_equal ["route_1", "route_2", "route_3"], @machine.events
    end

    def test_triggerable_events
      assert_equal ["route_1", "route_2"], @machine.triggerable_events

      @machine.trigger("route_1")
      assert_equal ["route_3"], @machine.triggerable_events

      @machine.trigger("route_3")
      assert_equal [], @machine.triggerable_events
    end

    def test_reachable_states
      assert_equal ["station_b", "station_c"], @machine.reachable_states

      @machine.trigger("route_1")
      assert_equal ["station_c"], @machine.reachable_states

      @machine.trigger("route_3")
      assert_equal [], @machine.reachable_states
    end

    def test_finished
      refute @machine.finished?, "Should not be finished in 'station_a' state"

      @machine.trigger("route_1")
      refute @machine.finished?, "Should not be finished in 'station_b' state"

      @machine.trigger("route_3")
      assert @machine.finished?, "Should be finished in 'station_c' state"
    end

    def test_can_trigger
      assert @machine.can_trigger?("route_1")
      assert @machine.can_trigger?("route_2")
      refute @machine.can_trigger?("route_3")

      @machine.trigger("route_1")
      refute @machine.can_trigger?("route_1")
      refute @machine.can_trigger?("route_2")
      assert @machine.can_trigger?("route_3")
    end
  end

  class EcommerceTest < Test
    def setup
      system = StateJacket::TransitionSystem.new
      system.add cart: [:submitted, :abandoned]
      system.add submitted: [:paid, :cancelled]
      system.add paid: :shipped
      system.add shipped: :delivered

      @machine = StateJacket::StateMachine.new(system, current_state: :cart)
      @machine.on :submit, cart: :submitted
      @machine.on :abandon, cart: :abandoned
      @machine.on :pay, submitted: :paid
      @machine.on :cancel, submitted: :cancelled
      @machine.on :ship, paid: :shipped
      @machine.on :deliver, shipped: :delivered
      @machine.lock
    end

    def test_to_h
      expected = {
        locked: true,
        current_state: "cart",
        finished: false,
        reachable_states: [
          "submitted",
          "abandoned"
        ],
        triggerable_events: [
          "submit",
          "abandon"
        ],
        rules: {
          "submit" => [
            {
              "cart" => "submitted"
            }
          ],
          "abandon" => [
            {
              "cart" => "abandoned"
            }
          ],
          "pay" => [
            {
              "submitted" => "paid"
            }
          ],
          "cancel" => [
            {
              "submitted" => "cancelled"
            }
          ],
          "ship" => [
            {
              "paid" => "shipped"
            }
          ],
          "deliver" => [
            {
              "shipped" => "delivered"
            }
          ]
        }
      }

      assert_equal expected, @machine.to_h
    end

    def test_current_state_through_order_lifecycle
      assert_equal "cart", @machine.current_state

      @machine.trigger("submit")
      assert_equal "submitted", @machine.current_state

      @machine.trigger("pay")
      assert_equal "paid", @machine.current_state

      @machine.trigger("ship")
      assert_equal "shipped", @machine.current_state

      @machine.trigger("deliver")
      assert_equal "delivered", @machine.current_state
    end

    def test_events
      assert_equal ["submit", "abandon", "pay", "cancel", "ship", "deliver"], @machine.events
    end

    def test_triggerable_events_through_lifecycle
      assert_equal ["submit", "abandon"], @machine.triggerable_events

      @machine.trigger("submit")
      assert_equal ["pay", "cancel"], @machine.triggerable_events

      @machine.trigger("pay")
      assert_equal ["ship"], @machine.triggerable_events

      @machine.trigger("ship")
      assert_equal ["deliver"], @machine.triggerable_events

      @machine.trigger("deliver")
      assert_equal [], @machine.triggerable_events
    end

    def test_reachable_states_through_lifecycle
      assert_equal ["submitted", "abandoned"], @machine.reachable_states

      @machine.trigger("submit")
      assert_equal ["paid", "cancelled"], @machine.reachable_states

      @machine.trigger("pay")
      assert_equal ["shipped"], @machine.reachable_states

      @machine.trigger("ship")
      assert_equal ["delivered"], @machine.reachable_states

      @machine.trigger("deliver")
      assert_equal [], @machine.reachable_states
    end

    def test_finished
      refute @machine.finished?, "Should not be finished in 'cart' state"

      # Try abandoned path
      machine_abandoned = StateJacket::StateMachine.new(
        @machine.transition_system,
        current_state: :cart
      )
      machine_abandoned.on :submit, cart: :submitted
      machine_abandoned.on :abandon, cart: :abandoned
      machine_abandoned.lock

      machine_abandoned.trigger("abandon")
      assert machine_abandoned.finished?, "Should be finished in 'abandoned' state"

      # Try complete order path
      @machine.trigger("submit")
      refute @machine.finished?

      @machine.trigger("pay")
      refute @machine.finished?

      @machine.trigger("ship")
      refute @machine.finished?

      @machine.trigger("deliver")
      assert @machine.finished?, "Should be finished in 'delivered' state"
    end

    def test_can_trigger_through_lifecycle
      assert @machine.can_trigger?("submit")
      assert @machine.can_trigger?("abandon")
      refute @machine.can_trigger?("pay")

      @machine.trigger("submit")
      refute @machine.can_trigger?("submit")
      refute @machine.can_trigger?("abandon")
      assert @machine.can_trigger?("pay")
      assert @machine.can_trigger?("cancel")
      refute @machine.can_trigger?("ship")

      @machine.trigger("pay")
      refute @machine.can_trigger?("pay")
      refute @machine.can_trigger?("cancel")
      assert @machine.can_trigger?("ship")

      @machine.trigger("ship")
      refute @machine.can_trigger?("ship")
      assert @machine.can_trigger?("deliver")
    end
  end

  class OrderProcessorTest < Test
    def setup
      system = StateJacket::TransitionSystem.new
      system.add cart: [:submitted, :abandoned]
      system.add submitted: [:paid, :cancelled]
      system.add paid: [:shipped, :refunded]
      system.add shipped: [:delivered, :returned]

      @machine = StateJacket::StateMachine.new(system, current_state: :cart)
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

    def test_to_h
      expected = {
        locked: true,
        current_state: "cart",
        finished: false,
        reachable_states: [
          "submitted",
          "abandoned"
        ],
        triggerable_events: [
          "submit",
          "abandon"
        ],
        rules: {
          "submit" => [
            {
              "cart" => "submitted"
            }
          ],
          "abandon" => [
            {
              "cart" => "abandoned"
            }
          ],
          "pay" => [
            {
              "submitted" => "paid"
            }
          ],
          "cancel" => [
            {
              "submitted" => "cancelled"
            }
          ],
          "ship" => [
            {
              "paid" => "shipped"
            }
          ],
          "refund" => [
            {
              "paid" => "refunded"
            }
          ],
          "deliver" => [
            {
              "shipped" => "delivered"
            }
          ],
          "return" => [
            {
              "shipped" => "returned"
            }
          ]
        }
      }

      assert_equal expected, @machine.to_h
    end

    def test_current_state_through_refund_path
      assert_equal "cart", @machine.current_state

      @machine.trigger("submit")
      assert_equal "submitted", @machine.current_state

      @machine.trigger("pay")
      assert_equal "paid", @machine.current_state

      @machine.trigger("refund")
      assert_equal "refunded", @machine.current_state
    end

    def test_current_state_through_return_path
      assert_equal "cart", @machine.current_state

      @machine.trigger("submit")
      assert_equal "submitted", @machine.current_state

      @machine.trigger("pay")
      assert_equal "paid", @machine.current_state

      @machine.trigger("ship")
      assert_equal "shipped", @machine.current_state

      @machine.trigger("return")
      assert_equal "returned", @machine.current_state
    end

    def test_events
      expected_events = [
        "submit", "abandon", "pay", "cancel",
        "ship", "refund", "deliver", "return"
      ]
      assert_equal expected_events, @machine.events
    end

    def test_triggerable_events_through_return_path
      assert_equal ["submit", "abandon"], @machine.triggerable_events

      @machine.trigger("submit")
      assert_equal ["pay", "cancel"], @machine.triggerable_events

      @machine.trigger("pay")
      assert_equal ["ship", "refund"], @machine.triggerable_events

      @machine.trigger("ship")
      assert_equal ["deliver", "return"], @machine.triggerable_events
    end

    def test_reachable_states_through_return_path
      assert_equal ["submitted", "abandoned"], @machine.reachable_states

      @machine.trigger("submit")
      assert_equal ["paid", "cancelled"], @machine.reachable_states

      @machine.trigger("pay")
      assert_equal ["shipped", "refunded"], @machine.reachable_states

      @machine.trigger("ship")
      assert_equal ["delivered", "returned"], @machine.reachable_states
    end

    def test_finished_terminal_states
      # Test all terminal states
      # Abandoned path
      machine1 = StateJacket::StateMachine.new(
        @machine.transition_system,
        current_state: :cart
      )
      machine1.on :submit, cart: :submitted
      machine1.on :abandon, cart: :abandoned
      machine1.lock

      machine1.trigger("abandon")
      assert machine1.finished?, "Should be finished in 'abandoned' state"

      # Cancelled path
      machine2 = StateJacket::StateMachine.new(
        @machine.transition_system,
        current_state: :cart
      )
      machine2.on :submit, cart: :submitted
      machine2.on :cancel, submitted: :cancelled
      machine2.lock

      machine2.trigger("submit")
      machine2.trigger("cancel")
      assert machine2.finished?, "Should be finished in 'cancelled' state"

      # Refunded path
      machine3 = StateJacket::StateMachine.new(
        @machine.transition_system,
        current_state: :cart
      )
      machine3.on :submit, cart: :submitted
      machine3.on :pay, submitted: :paid
      machine3.on :refund, paid: :refunded
      machine3.lock

      machine3.trigger("submit")
      machine3.trigger("pay")
      machine3.trigger("refund")
      assert machine3.finished?, "Should be finished in 'refunded' state"
    end

    def test_can_trigger_for_both_paths
      assert @machine.can_trigger?("submit")
      assert @machine.can_trigger?("abandon")

      @machine.trigger("submit")
      assert @machine.can_trigger?("pay")
      assert @machine.can_trigger?("cancel")

      @machine.trigger("pay")
      assert @machine.can_trigger?("ship")
      assert @machine.can_trigger?("refund")

      # Test shipped path
      machine_shipped = StateJacket::StateMachine.new(
        @machine.transition_system,
        current_state: :paid
      )
      machine_shipped.on :ship, paid: :shipped
      machine_shipped.on :deliver, shipped: :delivered
      machine_shipped.on :return, shipped: :returned
      machine_shipped.lock

      machine_shipped.trigger("ship")
      assert machine_shipped.can_trigger?("deliver")
      assert machine_shipped.can_trigger?("return")
      refute machine_shipped.can_trigger?("ship")
    end
  end

  class UserAccountTest < Test
    def setup
      system = StateJacket::TransitionSystem.new
      system.add pending: [:active, :rejected]
      system.add active: [:suspended, :deactivated]
      system.add suspended: [:active, :deactivated]
      system.add deactivated: :active # Loops back

      @machine = StateJacket::StateMachine.new(system, current_state: :pending)
      @machine.on :activate, pending: :active
      @machine.on :reject, pending: :rejected
      @machine.on :suspend, active: :suspended
      @machine.on :deactivate, active: :deactivated
      @machine.on :reactivate, suspended: :active
      @machine.on :perma_deactivate, suspended: :deactivated
      @machine.on :reopen, deactivated: :active # Cyclic transition
      @machine.lock
    end

    def test_to_h
      expected = {
        locked: true,
        current_state: "pending",
        finished: false,
        reachable_states: [
          "active",
          "rejected"
        ],
        triggerable_events: [
          "activate",
          "reject"
        ],
        rules: {
          "activate" => [
            {
              "pending" => "active"
            }
          ],
          "reject" => [
            {
              "pending" => "rejected"
            }
          ],
          "suspend" => [
            {
              "active" => "suspended"
            }
          ],
          "deactivate" => [
            {
              "active" => "deactivated"
            }
          ],
          "reactivate" => [
            {
              "suspended" => "active"
            }
          ],
          "perma_deactivate" => [
            {
              "suspended" => "deactivated"
            }
          ],
          "reopen" => [
            {
              "deactivated" => "active"
            }
          ]
        }
      }

      assert_equal expected, @machine.to_h
    end

    def test_current_state_through_lifecycle_with_loops
      assert_equal "pending", @machine.current_state

      @machine.trigger("activate")
      assert_equal "active", @machine.current_state

      @machine.trigger("suspend")
      assert_equal "suspended", @machine.current_state

      @machine.trigger("reactivate") # Loop back to active
      assert_equal "active", @machine.current_state

      @machine.trigger("deactivate")
      assert_equal "deactivated", @machine.current_state

      @machine.trigger("reopen") # Loop back to active
      assert_equal "active", @machine.current_state
    end

    def test_events
      expected_events = [
        "activate", "reject", "suspend", "deactivate",
        "reactivate", "perma_deactivate", "reopen"
      ]
      assert_equal expected_events, @machine.events
    end

    def test_triggerable_events_through_lifecycle
      assert_equal ["activate", "reject"], @machine.triggerable_events

      @machine.trigger("activate")
      assert_equal ["suspend", "deactivate"], @machine.triggerable_events

      @machine.trigger("suspend")
      assert_equal ["reactivate", "perma_deactivate"], @machine.triggerable_events

      @machine.trigger("reactivate") # Back to active
      assert_equal ["suspend", "deactivate"], @machine.triggerable_events

      @machine.trigger("deactivate")
      assert_equal ["reopen"], @machine.triggerable_events

      @machine.trigger("reopen") # Back to active
      assert_equal ["suspend", "deactivate"], @machine.triggerable_events
    end

    def test_reachable_states_through_lifecycle
      assert_equal ["active", "rejected"], @machine.reachable_states

      @machine.trigger("activate")
      assert_equal ["suspended", "deactivated"], @machine.reachable_states

      @machine.trigger("suspend")
      assert_equal ["active", "deactivated"], @machine.reachable_states

      @machine.trigger("reactivate") # Back to active
      assert_equal ["suspended", "deactivated"], @machine.reachable_states
    end

    def test_finished
      refute @machine.finished?, "Should not be finished in 'pending' state"

      # Only rejected is terminal
      @machine.trigger("reject")
      assert @machine.finished?, "Should be finished in 'rejected' state"

      # Other states aren't terminal due to the loops
      machine2 = StateJacket::StateMachine.new(
        @machine.transition_system,
        current_state: :pending
      )
      machine2.on :activate, pending: :active
      machine2.lock

      machine2.trigger("activate")
      refute machine2.finished?, "Should not be finished in 'active' state"
    end

    def test_can_trigger_with_cycles
      assert @machine.can_trigger?("activate")
      assert @machine.can_trigger?("reject")

      @machine.trigger("activate")
      assert @machine.can_trigger?("suspend")
      assert @machine.can_trigger?("deactivate")

      @machine.trigger("suspend")
      assert @machine.can_trigger?("reactivate") # Can go back to active
      assert @machine.can_trigger?("perma_deactivate")

      @machine.trigger("reactivate") # Back to active
      assert @machine.can_trigger?("suspend") # Can cycle again
      assert @machine.can_trigger?("deactivate")

      @machine.trigger("deactivate")
      assert @machine.can_trigger?("reopen") # Can go back to active

      @machine.trigger("reopen") # Back to active
      assert @machine.can_trigger?("suspend") # Can cycle again
    end
  end
end
