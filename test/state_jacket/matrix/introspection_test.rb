# frozen_string_literal: true

require_relative "../../test_helper"

class StateJacket::Matrix::IntrospectionTest < Minitest::Test
  # Test using the basic workflow example from the README
  class BasicWorkflowTest < Minitest::Test
    def setup
      @matrix = StateJacket::Matrix.new
      @matrix.add created: :started
      @matrix.add started: [:paused, :stopped]
      @matrix.add paused: :started
      @matrix.lock
    end

    def test_to_h
      hash = @matrix.to_h

      assert_kind_of Hash, hash
      assert_equal true, hash[:locked]
      assert_equal ["created", "paused", "started", "stopped"].sort, hash[:states].sort
      assert_equal ["created", "paused", "started"].sort, hash[:transitioners].sort
      assert_equal ["stopped"].sort, hash[:terminals].sort

      # Test transitions are included
      assert_kind_of Hash, hash[:transitions]
      expected_transitions = {
        created_to_started: {"created" => "started"},
        started_to_paused: {"started" => "paused"},
        started_to_stopped: {"started" => "stopped"},
        paused_to_started: {"paused" => "started"}
      }
      assert_equal expected_transitions, hash[:transitions]

      # Also test to_hash alias
      assert_equal hash, @matrix.to_hash
    end

    def test_states
      assert_equal ["created", "paused", "started", "stopped"].sort, @matrix.states.sort
    end

    def test_transitioners
      assert_equal ["created", "paused", "started"].sort, @matrix.transitioners.sort
    end

    def test_terminals
      assert_equal ["stopped"].sort, @matrix.terminals.sort
    end

    def test_locked_status_and_idempotency
      # Already locked in setup
      assert @matrix.locked?

      # Locking should be idempotent
      assert_same @matrix, @matrix.lock
      assert @matrix.locked?

      # Should not be able to add states after locking
      assert_raises(StateJacket::Matrix::Error) { @matrix.add(:new_state) }
    end

    def test_state_predicate
      assert @matrix.include?("created")
      assert @matrix.include?("started")
      assert @matrix.include?("paused")
      assert @matrix.include?("stopped")
      refute @matrix.include?("nonexistent")
    end

    def test_terminal_predicate
      refute @matrix.terminal?("created")
      refute @matrix.terminal?("started")
      refute @matrix.terminal?("paused")
      assert @matrix.terminal?("stopped")
      refute @matrix.terminal?("nonexistent")
    end

    def test_transitioner_predicate
      assert @matrix.transitioner?("created")
      assert @matrix.transitioner?("started")
      assert @matrix.transitioner?("paused")
      refute @matrix.transitioner?("stopped")
      refute @matrix.transitioner?("nonexistent")
    end

    def test_match_transition_behavior
      # Direct matches
      assert @matrix.match?(created: :started)
      assert @matrix.match?(started: [:paused, :stopped])
      assert @matrix.match?(paused: :started)

      # Non-matches
      refute @matrix.match?(created: :paused)
      refute @matrix.match?(started: :created)
      refute @matrix.match?(paused: :stopped)
      refute @matrix.match?(stopped: :created)

      # Partial matches
      refute @matrix.match?(started: :paused)
      refute @matrix.match?(started: :stopped)

      # Invalid states
      refute @matrix.match?(nonexistent: :created)
    end

    def test_allows_transition_behavior
      assert @matrix.allows?(created: :started)
      assert @matrix.allows?(started: :paused)
      assert @matrix.allows?(started: :stopped)
      assert @matrix.allows?(paused: :started)

      refute @matrix.allows?(created: :paused)
      refute @matrix.allows?(paused: :stopped)
      refute @matrix.allows?(stopped: :created)
      refute @matrix.allows?(started: :created)
    end

    def test_overlaps_transition_behavior
      # Direct overlaps
      assert @matrix.overlaps?(created: :started)
      assert @matrix.overlaps?(started: [:paused, :stopped])
      assert @matrix.overlaps?(paused: :started)

      # Partial overlaps
      assert @matrix.overlaps?(started: :paused)
      assert @matrix.overlaps?(started: :stopped)

      # No overlaps
      refute @matrix.overlaps?(created: :paused)
      refute @matrix.overlaps?(paused: :stopped)
      refute @matrix.overlaps?(stopped: :created)

      # Non-existent states
      refute @matrix.overlaps?(nonexistent: :created)
    end

    def test_deconstruct_keys
      # Test with specific keys
      result = @matrix.deconstruct_keys([:locked, :states])
      assert_equal true, result[:locked]
      assert_equal ["created", "paused", "started", "stopped"].sort, result[:states].sort
      assert_nil result[:terminals]

      # Test with nil (should return all)
      result = @matrix.deconstruct_keys(nil)
      assert_equal @matrix.to_hash, result
    end

    def test_to_h_unlocked_matrix
      unlocked_matrix = StateJacket::Matrix.new
      unlocked_matrix.add created: :started

      hash = unlocked_matrix.to_h
      assert_equal false, hash[:locked]
      assert_kind_of Hash, hash[:transitions]
      assert_equal({created_to_started: {"created" => "started"}}, hash[:transitions])
    end

    def test_transition_keys
      expected_keys = [
        :created_to_started,
        :started_to_paused,
        :started_to_stopped,
        :paused_to_started
      ].sort

      assert_equal expected_keys, @matrix.transition_keys.sort
    end

    def test_transition_indexing
      # Test valid transitions
      assert_equal({"created" => "started"}, @matrix[:created_to_started])
      assert_equal({"started" => "paused"}, @matrix[:started_to_paused])
      assert_equal({"started" => "stopped"}, @matrix[:started_to_stopped])
      assert_equal({"paused" => "started"}, @matrix[:paused_to_started])

      # Test with string keys
      assert_equal({"created" => "started"}, @matrix["created_to_started"])
    end

    def test_transition_indexing_errors
      # Test invalid transition key
      error = assert_raises(StateJacket::Matrix::Error) { @matrix[:invalid_transition] }
      assert_includes error.message, "transition 'invalid_transition' not found"
      assert_includes error.message, "Available transitions:"
    end

    def test_transition_indexing_with_unlocked_matrix
      unlocked_matrix = StateJacket::Matrix.new
      unlocked_matrix.add created: :started
      unlocked_matrix.add started: :stopped

      # Test that transitions work even when unlocked
      transition = unlocked_matrix[:created_to_started]
      assert_equal({"created" => "started"}, transition)
      assert transition.frozen?, "Unlocked matrix transitions should be frozen"

      # Test transition_keys works when unlocked
      assert_equal [:created_to_started, :started_to_stopped], unlocked_matrix.transition_keys.sort
    end

    def test_introspection_immutability
      # Test states immutability
      states = @matrix.states
      assert states.frozen?, "states should be frozen"
      assert_raises(FrozenError) { states << "hacked" }
      assert_raises(FrozenError) { states[0] = "hacked" }
      assert_raises(FrozenError) { states.clear }

      # Test transitioners immutability
      transitioners = @matrix.transitioners
      assert transitioners.frozen?, "transitioners should be frozen"
      assert_raises(FrozenError) { transitioners << "hacked" }
      assert_raises(FrozenError) { transitioners[0] = "hacked" }
      assert_raises(FrozenError) { transitioners.pop }

      # Test terminals immutability
      terminals = @matrix.terminals
      assert terminals.frozen?, "terminals should be frozen"
      assert_raises(FrozenError) { terminals << "hacked" }
      assert_raises(FrozenError) { terminals.delete_at(0) }

      # Test rules immutability
      rules = @matrix.rules
      assert rules.frozen?, "rules should be frozen"
      assert_raises(FrozenError) { rules["created"] = ["hacked"] }
      assert_raises(FrozenError) { rules.delete("created") }

      # Test rules values immutability
      started_rules = rules["started"]
      assert started_rules.frozen?, "rules values should be frozen"
      assert_raises(FrozenError) { started_rules << "hacked" }
      assert_raises(FrozenError) { started_rules[0] = "hacked" }

      # Test transitions immutability
      transitions = @matrix.transitions
      assert transitions.frozen?, "transitions should be frozen"
      assert_raises(FrozenError) { transitions[:new_key] = {"foo" => "bar"} }
      assert_raises(FrozenError) { transitions.delete(:created_to_started) }

      # Test individual transition immutability
      transition = @matrix[:created_to_started]
      assert transition.frozen?, "individual transitions should be frozen"
      assert_raises(FrozenError) { transition["created"] = "hacked" }
      assert_raises(FrozenError) { transition["new_key"] = "value" }

      # Test transition_keys immutability (array itself shouldn't be frozen as it's computed)
      keys = @matrix.transition_keys
      refute keys.frozen?, "transition_keys returns a new array each time"

      # But modifying it shouldn't affect the matrix
      original_keys = @matrix.transition_keys.dup
      keys << :fake_transition
      assert_equal original_keys, @matrix.transition_keys
    end

    def test_introspection_immutability_unlocked_matrix
      unlocked_matrix = StateJacket::Matrix.new
      unlocked_matrix.add created: :started
      unlocked_matrix.add started: :stopped

      # Test that unlocked matrix also returns frozen data
      states = unlocked_matrix.states
      assert states.frozen?, "unlocked matrix states should be frozen"
      assert_raises(FrozenError) { states << "hacked" }

      rules = unlocked_matrix.rules
      assert rules.frozen?, "unlocked matrix rules should be frozen"
      assert_raises(FrozenError) { rules["created"] = ["hacked"] }

      transitions = unlocked_matrix.transitions
      assert transitions.frozen?, "unlocked matrix transitions should be frozen"
      assert_raises(FrozenError) { transitions[:fake] = {"fake" => "data"} }
    end

    def test_to_h_immutability
      hash = @matrix.to_h

      # Test top-level immutability
      assert hash.frozen?, "to_h should return frozen hash"
      assert_raises(FrozenError) { hash[:new_key] = "value" }
      assert_raises(FrozenError) { hash.delete(:states) }

      # Test nested immutability
      assert_raises(FrozenError) { hash[:states] << "hacked" }
      assert_raises(FrozenError) { hash[:rules]["created"] = ["hacked"] }
      assert_raises(FrozenError) { hash[:rules]["started"] << "hacked" }
      assert_raises(FrozenError) { hash[:transitions][:created_to_started]["created"] = "hacked" }
    end
  end

  # Test using the document workflow example from the README
  class DocumentWorkflowTest < Minitest::Test
    def setup
      @matrix = StateJacket::Matrix.new
      @matrix.add drafted: :reviewed
      @matrix.add reviewed: [:approved, :rejected]
      @matrix.add approved: :published
      @matrix.add rejected: :drafted
      @matrix.lock
    end

    def test_to_h
      hash = @matrix.to_h

      assert_kind_of Hash, hash
      assert_equal true, hash[:locked]
      assert_equal ["approved", "drafted", "published", "rejected", "reviewed"].sort, hash[:states].sort
      assert_equal ["approved", "drafted", "rejected", "reviewed"].sort, hash[:transitioners].sort
      assert_equal ["published"].sort, hash[:terminals].sort

      # Test transitions are included
      assert_kind_of Hash, hash[:transitions]
      expected_transitions = {
        drafted_to_reviewed: {"drafted" => "reviewed"},
        reviewed_to_approved: {"reviewed" => "approved"},
        reviewed_to_rejected: {"reviewed" => "rejected"},
        approved_to_published: {"approved" => "published"},
        rejected_to_drafted: {"rejected" => "drafted"}
      }
      assert_equal expected_transitions, hash[:transitions]

      # Also test to_hash alias
      assert_equal hash, @matrix.to_hash
    end

    def test_states
      assert_equal ["approved", "drafted", "published", "rejected", "reviewed"].sort, @matrix.states.sort
    end

    def test_transitioners
      assert_equal ["approved", "drafted", "rejected", "reviewed"].sort, @matrix.transitioners.sort
    end

    def test_terminals
      assert_equal ["published"].sort, @matrix.terminals.sort
    end

    def test_locked_status_and_idempotency
      # Already locked in setup
      assert @matrix.locked?

      # Locking should be idempotent
      assert_same @matrix, @matrix.lock
      assert @matrix.locked?

      # Should not be able to add states after locking
      assert_raises(StateJacket::Matrix::Error) { @matrix.add(:new_state) }
    end

    def test_state_predicate
      assert @matrix.include?("drafted")
      assert @matrix.include?("reviewed")
      assert @matrix.include?("approved")
      assert @matrix.include?("rejected")
      assert @matrix.include?("published")
      refute @matrix.include?("nonexistent")
    end

    def test_terminal_predicate
      refute @matrix.terminal?("drafted")
      refute @matrix.terminal?("reviewed")
      refute @matrix.terminal?("approved")
      refute @matrix.terminal?("rejected")
      assert @matrix.terminal?("published")
      refute @matrix.terminal?("nonexistent")
    end

    def test_transitioner_predicate
      assert @matrix.transitioner?("drafted")
      assert @matrix.transitioner?("reviewed")
      assert @matrix.transitioner?("approved")
      assert @matrix.transitioner?("rejected")
      refute @matrix.transitioner?("published")
      refute @matrix.transitioner?("nonexistent")
    end

    def test_match_transition_behavior
      # Direct matches
      assert @matrix.match?(drafted: :reviewed)
      assert @matrix.match?(reviewed: [:approved, :rejected])
      assert @matrix.match?(approved: :published)
      assert @matrix.match?(rejected: :drafted)

      # Non-matches
      refute @matrix.match?(drafted: :approved)
      refute @matrix.match?(reviewed: :drafted)
      refute @matrix.match?(published: :approved)

      # Partial matches
      refute @matrix.match?(reviewed: :approved)
      refute @matrix.match?(reviewed: :rejected)
    end

    def test_allows_transition_behavior
      assert @matrix.allows?(drafted: :reviewed)
      assert @matrix.allows?(reviewed: :approved)
      assert @matrix.allows?(reviewed: :rejected)
      assert @matrix.allows?(approved: :published)
      assert @matrix.allows?(rejected: :drafted)

      refute @matrix.allows?(drafted: :approved)
      refute @matrix.allows?(published: :drafted)
      refute @matrix.allows?(approved: :rejected)
    end

    def test_overlaps_transition_behavior
      # Direct overlaps
      assert @matrix.overlaps?(drafted: :reviewed)
      assert @matrix.overlaps?(reviewed: [:approved, :rejected])
      assert @matrix.overlaps?(approved: :published)
      assert @matrix.overlaps?(rejected: :drafted)

      # Partial overlaps
      assert @matrix.overlaps?(reviewed: :approved)
      assert @matrix.overlaps?(reviewed: :rejected)

      # No overlaps
      refute @matrix.overlaps?(drafted: :published)
      refute @matrix.overlaps?(published: :drafted)
      refute @matrix.overlaps?(approved: :rejected)
    end

    def test_deconstruct_keys
      # Test with specific keys
      result = @matrix.deconstruct_keys([:locked, :transitioners])
      assert_equal true, result[:locked]
      assert_equal ["approved", "drafted", "rejected", "reviewed"].sort, result[:transitioners].sort
      assert_nil result[:states]

      # Test with nil (should return all)
      result = @matrix.deconstruct_keys(nil)
      assert_equal @matrix.to_hash, result
    end

    def test_transition_keys
      expected_keys = [
        :drafted_to_reviewed,
        :reviewed_to_approved,
        :reviewed_to_rejected,
        :approved_to_published,
        :rejected_to_drafted
      ].sort

      assert_equal expected_keys, @matrix.transition_keys.sort
    end

    def test_transition_indexing
      assert_equal({"drafted" => "reviewed"}, @matrix[:drafted_to_reviewed])
      assert_equal({"reviewed" => "approved"}, @matrix[:reviewed_to_approved])
      assert_equal({"reviewed" => "rejected"}, @matrix[:reviewed_to_rejected])
      assert_equal({"approved" => "published"}, @matrix[:approved_to_published])
      assert_equal({"rejected" => "drafted"}, @matrix[:rejected_to_drafted])
    end
  end

  # Test using the e-commerce workflow example from the README
  class EcommerceWorkflowTest < Minitest::Test
    def setup
      @matrix = StateJacket::Matrix.new
      @matrix.add cart_created: :cart_updated
      @matrix.add cart_updated: [:order_submitted, :cart_abandoned]
      @matrix.add order_submitted: [:payment_received, :payment_declined]
      @matrix.add payment_received: [:order_shipped, :payment_refunded]
      @matrix.add order_shipped: :order_delivered
      @matrix.lock
    end

    def test_to_h
      hash = @matrix.to_h

      assert_kind_of Hash, hash
      assert_equal true, hash[:locked]

      expected_states = [
        "cart_created", "cart_updated", "order_submitted", "cart_abandoned",
        "payment_received", "payment_declined", "order_shipped",
        "payment_refunded", "order_delivered"
      ].sort

      expected_transitioners = [
        "cart_created", "cart_updated", "order_submitted",
        "payment_received", "order_shipped"
      ].sort

      expected_terminals = [
        "cart_abandoned", "payment_declined",
        "payment_refunded", "order_delivered"
      ].sort

      assert_equal expected_states, hash[:states].sort
      assert_equal expected_transitioners, hash[:transitioners].sort
      assert_equal expected_terminals, hash[:terminals].sort

      # Test transitions are included
      assert_kind_of Hash, hash[:transitions]
      expected_transitions = {
        cart_created_to_cart_updated: {"cart_created" => "cart_updated"},
        cart_updated_to_order_submitted: {"cart_updated" => "order_submitted"},
        cart_updated_to_cart_abandoned: {"cart_updated" => "cart_abandoned"},
        order_submitted_to_payment_received: {"order_submitted" => "payment_received"},
        order_submitted_to_payment_declined: {"order_submitted" => "payment_declined"},
        payment_received_to_order_shipped: {"payment_received" => "order_shipped"},
        payment_received_to_payment_refunded: {"payment_received" => "payment_refunded"},
        order_shipped_to_order_delivered: {"order_shipped" => "order_delivered"}
      }
      assert_equal expected_transitions, hash[:transitions]

      # Also test to_hash alias
      assert_equal hash, @matrix.to_hash
    end

    def test_states
      expected_states = [
        "cart_created", "cart_updated", "order_submitted", "cart_abandoned",
        "payment_received", "payment_declined", "order_shipped",
        "payment_refunded", "order_delivered"
      ].sort

      assert_equal expected_states, @matrix.states.sort
    end

    def test_transitioners
      expected_transitioners = [
        "cart_created", "cart_updated", "order_submitted",
        "payment_received", "order_shipped"
      ].sort

      assert_equal expected_transitioners, @matrix.transitioners.sort
    end

    def test_terminals
      expected_terminals = [
        "cart_abandoned", "payment_declined",
        "payment_refunded", "order_delivered"
      ].sort

      assert_equal expected_terminals, @matrix.terminals.sort
    end

    def test_locked_status_and_idempotency
      # Already locked in setup
      assert @matrix.locked?

      # Locking should be idempotent
      assert_same @matrix, @matrix.lock
      assert @matrix.locked?

      # Should not be able to add states after locking
      assert_raises(StateJacket::Matrix::Error) { @matrix.add(:new_state) }
    end

    def test_state_predicate
      assert @matrix.include?("cart_created")
      assert @matrix.include?("order_submitted")
      assert @matrix.include?("payment_received")
      assert @matrix.include?("order_delivered")
      refute @matrix.include?("nonexistent")
    end

    def test_terminal_predicate
      refute @matrix.terminal?("cart_created")
      refute @matrix.terminal?("order_submitted")
      assert @matrix.terminal?("cart_abandoned")
      assert @matrix.terminal?("payment_declined")
      assert @matrix.terminal?("payment_refunded")
      assert @matrix.terminal?("order_delivered")
      refute @matrix.terminal?("nonexistent")
    end

    def test_transitioner_predicate
      assert @matrix.transitioner?("cart_created")
      assert @matrix.transitioner?("cart_updated")
      assert @matrix.transitioner?("order_submitted")
      assert @matrix.transitioner?("payment_received")
      assert @matrix.transitioner?("order_shipped")
      refute @matrix.transitioner?("order_delivered")
      refute @matrix.transitioner?("nonexistent")
    end

    def test_match_transition_behavior
      # Direct matches
      assert @matrix.match?(cart_created: :cart_updated)
      assert @matrix.match?(cart_updated: [:order_submitted, :cart_abandoned])
      assert @matrix.match?(order_submitted: [:payment_received, :payment_declined])
      assert @matrix.match?(payment_received: [:order_shipped, :payment_refunded])
      assert @matrix.match?(order_shipped: :order_delivered)

      # Non-matches
      refute @matrix.match?(cart_created: :order_submitted)
      refute @matrix.match?(payment_declined: :order_shipped)
      refute @matrix.match?(order_delivered: :cart_created)

      # Partial matches
      refute @matrix.match?(cart_updated: :order_submitted)
      refute @matrix.match?(order_submitted: :payment_received)
    end

    def test_allows_transition_behavior
      assert @matrix.allows?(cart_created: :cart_updated)
      assert @matrix.allows?(cart_updated: :order_submitted)
      assert @matrix.allows?(cart_updated: :cart_abandoned)
      assert @matrix.allows?(order_submitted: :payment_received)
      assert @matrix.allows?(order_submitted: :payment_declined)
      assert @matrix.allows?(payment_received: :order_shipped)
      assert @matrix.allows?(payment_received: :payment_refunded)
      assert @matrix.allows?(order_shipped: :order_delivered)

      refute @matrix.allows?(cart_created: :order_submitted)
      refute @matrix.allows?(cart_created: :cart_abandoned)
      refute @matrix.allows?(cart_abandoned: :cart_created)
      refute @matrix.allows?(payment_declined: :payment_received)
      refute @matrix.allows?(order_delivered: :cart_created)
    end

    def test_overlaps_transition_behavior
      # Direct overlaps
      assert @matrix.overlaps?(cart_created: :cart_updated)
      assert @matrix.overlaps?(cart_updated: [:order_submitted, :cart_abandoned])
      assert @matrix.overlaps?(order_submitted: [:payment_received, :payment_declined])
      assert @matrix.overlaps?(payment_received: [:order_shipped, :payment_refunded])
      assert @matrix.overlaps?(order_shipped: :order_delivered)

      # Partial overlaps
      assert @matrix.overlaps?(cart_updated: :order_submitted)
      assert @matrix.overlaps?(cart_updated: :cart_abandoned)
      assert @matrix.overlaps?(order_submitted: :payment_received)
      assert @matrix.overlaps?(order_submitted: :payment_declined)
      assert @matrix.overlaps?(payment_received: :order_shipped)
      assert @matrix.overlaps?(payment_received: :payment_refunded)

      # No overlaps
      refute @matrix.overlaps?(cart_created: :order_submitted)
      refute @matrix.overlaps?(cart_abandoned: :cart_created)
      refute @matrix.overlaps?(order_delivered: :cart_created)
      refute @matrix.overlaps?(payment_declined: :payment_received)
    end

    def test_deconstruct_keys
      # Test with specific keys
      result = @matrix.deconstruct_keys([:terminals, :rules])
      expected_terminals = [
        "cart_abandoned", "payment_declined",
        "payment_refunded", "order_delivered"
      ].sort

      assert_equal expected_terminals, result[:terminals].sort
      assert_kind_of Hash, result[:rules]
      assert_nil result[:states]

      # Test with nil (should return all)
      result = @matrix.deconstruct_keys(nil)
      assert_equal @matrix.to_hash, result
    end
  end
end
