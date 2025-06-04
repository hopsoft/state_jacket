# frozen_string_literal: true

require_relative "../test_helper"

class StateJacket::TransitionResultTest < Test
  def test_transition_result_creation
    # Test creation with successful transition
    result = StateJacket::TransitionResult.new("event_name", "from_state", "to_state", :ok, nil)
    assert_equal "event_name", result.event
    assert_equal "from_state", result.from
    assert_equal "to_state", result.to
    assert_equal :ok, result.status
    assert_nil result.error

    # Test creation with error
    error = StandardError.new("Test error")
    result = StateJacket::TransitionResult.new("event_name", "from_state", "to_state", :error, error)
    assert_equal "event_name", result.event
    assert_equal "from_state", result.from
    assert_equal "to_state", result.to
    assert_equal :error, result.status
    assert_equal error, result.error
  end

  def test_successful_predicate
    # Test successful case
    result = StateJacket::TransitionResult.new("event_name", "from_state", "to_state", :ok, nil)
    assert result.successful?

    # Test error case
    error = StandardError.new("Test error")
    result = StateJacket::TransitionResult.new("event_name", "from_state", "to_state", :error, error)
    refute result.successful?

    # Test with other status values
    result = StateJacket::TransitionResult.new("event_name", "from_state", "to_state", :other, nil)
    refute result.successful?
  end

  def test_deconstruct_keys_with_nil
    result = StateJacket::TransitionResult.new("event_name", "from_state", "to_state", :ok, nil)
    hash = result.deconstruct_keys(nil)

    assert_equal result.to_h, hash
    assert_equal "event_name", hash[:event]
    assert_equal "from_state", hash[:from]
    assert_equal "to_state", hash[:to]
    assert_equal :ok, hash[:status]
    assert_nil hash[:error]
  end

  def test_deconstruct_keys_with_specified_keys
    result = StateJacket::TransitionResult.new("event_name", "from_state", "to_state", :ok, nil)
    hash = result.deconstruct_keys([:event, :status])

    assert_equal 2, hash.keys.size
    assert_equal "event_name", hash[:event]
    assert_equal :ok, hash[:status]
    refute hash.key?(:from)
    refute hash.key?(:to)
    refute hash.key?(:error)
  end

  def test_deconstruct_keys_with_empty_keys
    result = StateJacket::TransitionResult.new("event_name", "from_state", "to_state", :ok, nil)
    hash = result.deconstruct_keys([])

    assert_equal({}, hash)
  end

  def test_pattern_matching
    result = StateJacket::TransitionResult.new("event_name", "from_state", "to_state", :ok, nil)

    # Test basic pattern matching
    matched = case result
    in { event: "event_name", status: :ok }
      true
    else
      false
    end
    assert matched

    # Test pattern matching with wrong values
    matched = case result
    in { event: "wrong_name", status: :ok }
      true
    else
      false
    end
    refute matched

    # Test pattern matching with error
    error = StandardError.new("Test error")
    result_with_error = StateJacket::TransitionResult.new("event_name", "from_state", "to_state", :error, error)

    error_message = case result_with_error
    in { status: :error, error: error }
      error.message
    else
      "No error"
    end
    assert_equal "Test error", error_message
  end

  def test_pattern_matching_with_destructuring
    result = StateJacket::TransitionResult.new("event_name", "from_state", "to_state", :ok, nil)

    # Test pattern matching with variable binding
    case result
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
    result = StateJacket::TransitionResult.new("", "", "", :ok, nil)
    assert result.successful?
    assert_equal "", result.event

    # Test with symbol states (should be converted to strings)
    result = StateJacket::TransitionResult.new(:event_sym, :from_sym, :to_sym, :ok, nil)
    assert_equal :event_sym, result.event  # Struct doesn't auto-convert to string
    assert_equal :from_sym, result.from
    assert_equal :to_sym, result.to

    # Test with non-standard status
    result = StateJacket::TransitionResult.new("event", "from", "to", :custom_status, nil)
    refute result.successful?

    # Test with non-StandardError object
    non_error = Object.new
    result = StateJacket::TransitionResult.new("event", "from", "to", :error, non_error)
    assert_equal non_error, result.error
  end
end
