# frozen_string_literal: true

require_relative "test_helper"

class PatternMatchingTest < Minitest::Test
  def setup
    @transitions = StateJacket::StateTransitionSystem.new
    @transitions.add pending: [:approved, :rejected]
    @transitions.add approved: [:completed]
    @transitions.add rejected: [:pending]
    @transitions.add :completed
    @transitions.lock

    @machine = StateJacket::StateMachine.new(@transitions, state: :pending)
    @machine.on :approve, pending: :approved
    @machine.on :reject, pending: :rejected
    @machine.on :complete, approved: :completed
    @machine.on :retry, rejected: :pending
    @machine.lock
  end

  # StateMachine pattern matching tests
  def test_state_machine_deconstruct_keys
    case @machine
    in { state: "pending", triggerable_events: events }
      assert_includes events, "approve"
      assert_includes events, "reject"
    else
      flunk "Pattern matching failed"
    end
  end

  def test_state_machine_pattern_matching_with_terminal_state
    @machine.trigger(:approve)
    @machine.trigger(:complete)

    case @machine
    in { state: "completed", terminal?: true }
      # Expected match
    else
      flunk "Should match terminal state pattern"
    end
  end

  def test_state_machine_pattern_matching_with_reachable_states
    case @machine
    in { state: "pending", reachable_states: destinations }
      assert_includes destinations, "approved"
      assert_includes destinations, "rejected"
    else
      flunk "Should match reachable states pattern"
    end
  end

  def test_state_machine_pattern_matching_with_locked_status
    case @machine
    in { locked?: true, events: events }
      assert_includes events, "approve"
      assert_includes events, "reject"
      assert_includes events, "complete"
      assert_includes events, "retry"
    else
      flunk "Should match locked machine with events"
    end
  end

  # StateTransitionSystem pattern matching tests
  def test_state_transition_system_deconstruct_keys
    case @transitions
    in { states: states, locked?: true }
      assert_includes states, "pending"
      assert_includes states, "approved"
      assert_includes states, "rejected"
      assert_includes states, "completed"
    else
      flunk "Pattern matching failed"
    end
  end

  def test_state_transition_system_pattern_matching_with_transitioners
    case @transitions
    in { transitioners: trans, terminators: terms }
      assert_includes trans, "pending"
      assert_includes trans, "approved"
      assert_includes trans, "rejected"
      assert_includes terms, "completed"
    else
      flunk "Should match transitioners and terminators"
    end
  end

  def test_state_transition_system_pattern_matching_with_specific_counts
    case @transitions
    in { states: states, terminators: terms } if states.length == 4 && terms.length == 1
      assert_equal ["completed"], terms
    else
      flunk "Should match specific state and terminator counts"
    end
  end

  # TransitionResult pattern matching tests
  def test_transition_result_successful_array_pattern
    result = @machine.trigger(:approve)

    case result
    in StateJacket::TransitionResult[true, "pending", "approved", "approve"]
      # Expected match
    else
      flunk "Should match successful transition array pattern"
    end
  end

  def test_transition_result_successful_hash_pattern
    result = @machine.trigger(:approve)

    case result
    in { success?: true, from: "pending", to: "approved", event: "approve" }
      # Expected match
    else
      flunk "Should match successful transition hash pattern"
    end
  end

  def test_transition_result_failed_pattern
    # Try to trigger an event that can't execute from current state
    result = @machine.trigger(:retry) # Can't retry from pending

    case result
    in { failed?: true, from: "pending", to: nil, event: "retry" }
      # Expected match for failed transition
    else
      flunk "Should match failed transition pattern"
    end
  end

  def test_transition_result_failure_method_pattern
    result = @machine.trigger(:retry) # Invalid from pending

    case result
    in { failed?: true, from: "pending" }
      # Expected match
    else
      flunk "Should match failure pattern"
    end
  end

  def test_transition_result_array_deconstruct
    result = @machine.trigger(:approve)
    success, from, to, event = result.deconstruct

    assert_equal true, success
    assert_equal "pending", from
    assert_equal "approved", to
    assert_equal "approve", event
  end

  def test_transition_result_predicates
    success_result = @machine.trigger(:approve)
    assert success_result.success?
    refute success_result.failed?

    failure_result = @machine.trigger(:retry) # Invalid transition from pending
    refute failure_result.success?
    assert failure_result.failed?
  end

  # Complex pattern matching scenarios
  def test_complex_state_based_logic
    handle_machine_state = lambda do |machine|
      case machine
      in { state: "pending", actions: events } if events.include?("approve")
        :can_approve
      in { state: "approved", destinations: ["completed"] }
        :can_complete
      in { terminal?: true }
        :terminal
      else
        :unknown
      end
    end

    assert_equal :can_approve, handle_machine_state.call(@machine)

    @machine.trigger(:approve)
    assert_equal :can_complete, handle_machine_state.call(@machine)

    @machine.trigger(:complete)
    assert_equal :terminal, handle_machine_state.call(@machine)
  end

  def test_transition_result_routing
    route_transition_result = lambda do |result|
      case result
      in { success?: true, from: "pending", to: "approved" }
        :approval_path
      in { success?: true, from: "pending", to: "rejected" }
        :rejection_path
      in { success?: true, to: "completed" }
        :completion_path
      in { failed?: true, from: String => state }
        [:failure_path, state]
      else
        :unknown
      end
    end

    result1 = @machine.trigger(:approve)
    assert_equal :approval_path, route_transition_result.call(result1)

    result2 = @machine.trigger(:complete)
    assert_equal :completion_path, route_transition_result.call(result2)

    # Reset to test failure
    @machine = StateJacket::StateMachine.new(@transitions, state: :completed)
    @machine.on :retry, rejected: :pending # Only valid from rejected, not completed
    @machine.lock

    result3 = @machine.trigger(:retry) # Should fail from completed state
    assert_equal [:failure_path, "completed"], route_transition_result.call(result3)
  end

  def test_combined_machine_and_transition_patterns
    analyze_workflow = lambda do |machine, result|
      case [machine, result]
      in [{ state: "completed" }, { success?: true }]
        :workflow_complete
      in [{ terminal?: true }, { success?: false }]
        :terminal_with_failed_transition
      in [{ state: String => state }, { success?: true, to: String => new_state }]
        [:successful_transition, state, new_state]
      in [{ state: String => state }, { failed?: true }]
        [:failed_transition, state]
      else
        :unknown_scenario
      end
    end

    # Test successful transition to completion
    @machine.trigger(:approve)
    result = @machine.trigger(:complete)
    assert_equal :workflow_complete, analyze_workflow.call(@machine, result)

    # Test failed transition from terminal state
    failed_result = @machine.trigger(:approve) # Can't approve from completed
    assert_equal :terminal_with_failed_transition, analyze_workflow.call(@machine, failed_result)
  end

  # Edge cases and guards
  def test_pattern_matching_with_guards
    categorize_machine = lambda do |machine|
      case machine
      in { state: String => state, triggerable_events: [] }
        [:terminal, state]
      in { state: String => state, actions: events } if events.length > 1
        [:multiple_options, state, events.length]
      in { state: String => state, actions: [event] }
        [:single_option, state, event]
      else
        :unknown
      end
    end

    # Pending state has multiple options
    result = categorize_machine.call(@machine)
    assert_equal :multiple_options, result[0]
    assert_equal "pending", result[1]
    assert_equal 2, result[2]

    # Move to approved (single option)
    @machine.trigger(:approve)
    result = categorize_machine.call(@machine)
    assert_equal :single_option, result[0]
    assert_equal "approved", result[1]
    assert_equal "complete", result[2]

    # Move to completed (terminal)
    @machine.trigger(:complete)
    result = categorize_machine.call(@machine)
    assert_equal :terminal, result[0]
    assert_equal "completed", result[1]
  end

  def test_nested_pattern_matching
    complex_decision = lambda do |system, machine, user_role|
      case [system, machine, user_role]
      in [{ locked?: true }, { state: "pending", actions: events }, "admin"] if events.include?("approve")
        :admin_can_approve
      in [{ terminators: terms }, { state: String => state }, _] if terms.include?(state)
        :at_terminal_state
      in [{ states: states }, { state: String => state }, "user"] if states.include?(state)
        :user_viewing_valid_state
      else
        :access_denied
      end
    end

    assert_equal :admin_can_approve, complex_decision.call(@transitions, @machine, "admin")

    @machine.trigger(:approve)
    @machine.trigger(:complete)
    assert_equal :at_terminal_state, complex_decision.call(@transitions, @machine, "user")
  end

  def test_specialized_pattern_classes_transition_result
    # Test Success pattern
    success_result = @machine.trigger(:approve)

    case success_result
    when StateJacket::Patterns::Success
      # Should match successful transitions
    else
      flunk "Should match Success pattern"
    end

    # Test FromState pattern
    approval_pattern = StateJacket::Patterns::FromState[:pending]

    case success_result
    when approval_pattern
      # Should match specific transition
    else
      flunk "Should match FromState pattern"
    end

    # Test Failure pattern
    failure_result = @machine.trigger(:retry) # Invalid from pending

    case failure_result
    when StateJacket::Patterns::Failure
      # Should match failed transitions
    else
      flunk "Should match Failure pattern"
    end

    # Test StateChange pattern
    case success_result
    when StateJacket::Patterns::StateChange
      # Should match state changes
    else
      flunk "Should match StateChange pattern"
    end
  end

  def test_specialized_pattern_classes_state_machine
    # Test StateMachine::Patterns::PendingAction
    pending_approve = StateJacket::StateMachine::Patterns::PendingAction[:approve]

    case @machine
    when pending_approve
      # Should match machines that can approve
    else
      flunk "Should match PendingAction for approve"
    end

    # Test StateMachine::Patterns::InState
    pending_state = StateJacket::StateMachine::Patterns::InState[:pending]

    case @machine
    when pending_state
      # Should match machines in pending state
    else
      flunk "Should match InState for pending"
    end

    # Test StateMachine::Patterns::Active
    case @machine
    when StateJacket::StateMachine::Patterns::Active
      # Should match active (locked, non-terminal) machines
    else
      flunk "Should match Active pattern"
    end

    # Move to terminal state and test Terminal pattern
    @machine.trigger(:approve)
    @machine.trigger(:complete)

    case @machine
    when StateJacket::StateMachine::Patterns::Terminal
      # Should match terminal machines
    else
      flunk "Should match Terminal pattern"
    end
  end

  def test_specialized_core_patterns
    # Test CanReach pattern
    can_reach_completed = StateJacket::StateMachine::Patterns::CanReach[:completed]

    @machine.trigger(:approve) # Move to approved state

    case @machine
    when can_reach_completed
      # Should match machines that can reach completed state
    else
      flunk "Should match CanReach pattern"
    end

    # Test PendingAction pattern
    pending_complete = StateJacket::StateMachine::Patterns::PendingAction[:complete]

    case @machine
    when pending_complete
      # Should match machines that can trigger complete action
    else
      flunk "Should match PendingAction pattern"
    end
  end

  def test_specialized_pattern_complex_scenarios
    # Test combining multiple patterns in realistic scenario
    result = @machine.trigger(:approve)

    # Test individual patterns first
    success_matches = StateJacket::Patterns::Success === result
    active_matches = StateJacket::StateMachine::Patterns::Active === @machine

    assert success_matches, "Result should match Success pattern"
    assert active_matches, "Machine should match Active pattern"

    # Test combined pattern matching using individual checks
    action_taken = if (StateJacket::Patterns::Success === result) && (StateJacket::StateMachine::Patterns::Active === @machine)
      :successful_progression
    elsif (StateJacket::Patterns::Failure === result) && (StateJacket::StateMachine::Patterns::Active === @machine)
      :failed_but_can_retry
    elsif (StateJacket::Patterns::Success === result) && (StateJacket::StateMachine::Patterns::Terminal === @machine)
      :workflow_completed
    else
      :unknown_scenario
    end

    assert_equal :successful_progression, action_taken

    # Test specific transition patterns
    completion_result = @machine.trigger(:complete)

    case completion_result
    when StateJacket::Patterns::Completion
      # Should match completion transitions
    else
      flunk "Should match Completion pattern"
    end
  end

  # String representations and debugging
  def test_transition_result_string_representation
    result = @machine.trigger(:approve)
    assert_match(/struct.*TransitionResult.*success=true.*pending.*approved.*approve/, result.to_s)

    # Move to completed state and try invalid transition
    @machine.trigger(:approve)
    @machine.trigger(:complete)
    failure_result = @machine.trigger(:approve) # Invalid transition from completed
    assert_match(/struct.*TransitionResult.*success=false.*completed.*approve/, failure_result.to_s)
  end

  def test_transition_result_inspect
    result = @machine.trigger(:approve)
    assert_match(/struct.*TransitionResult.*success=true.*from_state="pending".*to_state="approved".*event="approve"/, result.inspect)
  end

  def test_transition_result_failed_inspect
    result = @machine.trigger(:retry) # Invalid from pending
    assert_match(/struct.*TransitionResult.*success=false.*from_state="pending".*to_state=nil.*event="retry"/, result.inspect)
  end

  # Backward compatibility
  def test_transition_result_maintains_state_access
    result = @machine.trigger(:approve)

    # New API
    assert_equal "approved", result.to_state
    assert result.success?

    # Machine state should still be updated
    assert_equal "approved", @machine.state
  end

  def test_pattern_matching_slice_behavior
    # Test that deconstruct_keys properly slices requested keys
    machine_keys = @machine.deconstruct_keys([:state, :terminal?])
    assert_equal({state: "pending", terminal?: false}, machine_keys)

    system_keys = @transitions.deconstruct_keys([:locked?, :states])
    expected = {locked?: true, states: @transitions.states.sort}
    actual = {locked?: system_keys[:locked?], states: system_keys[:states].sort}
    assert_equal expected, actual

    result = @machine.trigger(:approve)
    result_keys = result.deconstruct_keys([:success?, :from, :to])
    assert_equal({success?: true, from: "pending", to: "approved"}, result_keys)
  end
end
