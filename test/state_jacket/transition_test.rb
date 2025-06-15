# frozen_string_literal: true

require_relative "../test_helper"

class StateJacket::TransitionTest < Test
  def test_transition_creation
    # Test creation with successful transition
    transition = StateJacket::Transition.new("event_name", "from_state", "to_state", :ok, nil)
    assert_equal "event_name", transition.event
    assert_equal "from_state", transition.from
    assert_equal "to_state", transition.to
    assert_equal :ok, transition.status
    assert_nil transition.error

    # Test creation with error
    error = StandardError.new("Test error")
    transition = StateJacket::Transition.new("event_name", "from_state", "to_state", :error, error)
    assert_equal "event_name", transition.event
    assert_equal "from_state", transition.from
    assert_equal "to_state", transition.to
    assert_equal :error, transition.status
    assert_equal error, transition.error
  end

  def test_successful_predicate
    # Test successful case
    transition = StateJacket::Transition.new("event_name", "from_state", "to_state", :ok, nil)
    assert transition.successful?

    # Test error case
    error = StandardError.new("Test error")
    transition = StateJacket::Transition.new("event_name", "from_state", "to_state", :error, error)
    refute transition.successful?

    # Test with other status values
    transition = StateJacket::Transition.new("event_name", "from_state", "to_state", :other, nil)
    refute transition.successful?
  end

  def test_deconstruct_keys_with_nil
    transition = StateJacket::Transition.new("event_name", "from_state", "to_state", :ok, nil)
    hash = transition.deconstruct_keys(nil)

    assert_equal transition.to_h, hash
    assert_equal "event_name", hash[:event]
    assert_equal "from_state", hash[:from]
    assert_equal "to_state", hash[:to]
    assert_equal :ok, hash[:status]
    assert_nil hash[:error]
  end

  def test_deconstruct_keys_with_specified_keys
    transition = StateJacket::Transition.new("event_name", "from_state", "to_state", :ok, nil)
    hash = transition.deconstruct_keys([:event, :status])

    assert_equal 2, hash.keys.size
    assert_equal "event_name", hash[:event]
    assert_equal :ok, hash[:status]
    refute hash.key?(:from)
    refute hash.key?(:to)
    refute hash.key?(:error)
  end

  def test_deconstruct_keys_with_empty_keys
    transition = StateJacket::Transition.new("event_name", "from_state", "to_state", :ok, nil)
    hash = transition.deconstruct_keys([])

    assert_equal({}, hash)
  end

  def test_pattern_matching
    transition = StateJacket::Transition.new("event_name", "from_state", "to_state", :ok, nil)

    # Test basic pattern matching
    matched = case transition
    in { event: "event_name", status: :ok }
      true
    else
      false
    end
    assert matched

    # Test pattern matching with wrong values
    matched = case transition
    in { event: "wrong_name", status: :ok }
      true
    else
      false
    end
    refute matched

    # Test pattern matching with error
    error = StandardError.new("Test error")
    transition_with_error = StateJacket::Transition.new("event_name", "from_state", "to_state", :error, error)

    error_message = case transition_with_error
    in { status: :error, error: error }
      error.message
    else
      "No error"
    end
    assert_equal "Test error", error_message
  end

  def test_pattern_matching_with_destructuring
    transition = StateJacket::Transition.new("event_name", "from_state", "to_state", :ok, nil)

    # Test pattern matching with variable binding
    case transition
    in { event: event_var, from: from_var, to: to_var, status: status_var }
      assert_equal "event_name", event_var
      assert_equal "from_state", from_var
      assert_equal "to_state", to_var
      assert_equal :ok, status_var
    else
      flunk "Pattern matching failed"
    end
  end

  def test_edge_cases
    # Test with empty strings
    transition = StateJacket::Transition.new("", "", "", :ok, nil)
    assert transition.successful?
    assert_equal "", transition.event

    # Test with symbol states (should be converted to strings)
    transition = StateJacket::Transition.new(:event_sym, :from_sym, :to_sym, :ok, nil)
    assert_equal :event_sym, transition.event  # Struct doesn't auto-convert to string
    assert_equal :from_sym, transition.from
    assert_equal :to_sym, transition.to

    # Test with non-standard status
    transition = StateJacket::Transition.new("event", "from", "to", :custom_status, nil)
    refute transition.successful?

    # Test with non-StandardError object
    non_error = Object.new
    transition = StateJacket::Transition.new("event", "from", "to", :error, non_error)
    assert_equal non_error, transition.error
  end
end
