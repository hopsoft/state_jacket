# frozen_string_literal: true

require_relative "../../test_helper"

class StateJacket::StateMachine::WorkflowResumptionTest < Test
  # Tests focused on system and machine evolution between pauses
  class EvolutionTest < Test
    def test_transition_system_evolution
      # Start with a basic transition system with limited states
      initial_system = StateJacket::TransitionSystem.new
      initial_system.add order_placed: :processing
      initial_system.add processing: :packed
      initial_system.lock

      # Create a machine and run through the first part of workflow
      initial_machine = StateJacket::StateMachine.new(initial_system, current_state: :order_placed)
      initial_machine.on :process, order_placed: :processing
      initial_machine.on :pack, processing: :packed
      initial_machine.lock

      initial_machine.trigger(:process)
      assert_equal "processing", initial_machine.current_state

      # Save current state (simulating a pause in the workflow)
      saved_state = initial_machine.current_state

      # Later, the system evolves to include new states and transitions
      # This might happen due to business requirements changing or bugs being fixed
      evolved_system = StateJacket::TransitionSystem.new
      evolved_system.add order_placed: :processing
      evolved_system.add processing: [:packed, :cancelled]  # Added cancellation option
      evolved_system.add packed: [:shipped, :on_hold]       # Added new states
      evolved_system.add on_hold: :shipped                  # Added new transition
      evolved_system.add shipped: :delivered                # Extended the workflow
      evolved_system.lock

      # Resume workflow with the evolved transition system
      evolved_machine = StateJacket::StateMachine.new(evolved_system, current_state: saved_state)
      evolved_machine.on :pack, processing: :packed
      evolved_machine.on :cancel, processing: :cancelled    # New event
      evolved_machine.on :ship, packed: :shipped            # New future events
      evolved_machine.on :hold, packed: :on_hold            # New future events
      evolved_machine.on :release, on_hold: :shipped        # New future events
      evolved_machine.on :deliver, shipped: :delivered      # New future events
      evolved_machine.lock

      # Workflow can continue with the evolved system
      assert_equal "processing", evolved_machine.current_state
      assert_equal ["cancel", "pack"], evolved_machine.triggerable_events.sort

      # Continue with the new system
      evolved_machine.trigger(:pack)
      assert_equal "packed", evolved_machine.current_state

      # Can now use the new paths that weren't available in the original system
      assert_equal ["hold", "ship"], evolved_machine.triggerable_events.sort
      evolved_machine.trigger(:hold)
      assert_equal "on_hold", evolved_machine.current_state

      evolved_machine.trigger(:release)
      assert_equal "shipped", evolved_machine.current_state

      evolved_machine.trigger(:deliver)
      assert_equal "delivered", evolved_machine.current_state
      assert evolved_machine.finished?
    end

    def test_transition_system_evolution_pitfalls
      # Initial system and workflow
      initial_system = StateJacket::TransitionSystem.new
      initial_system.add pending: [:approved, :rejected]
      initial_system.lock

      machine = StateJacket::StateMachine.new(initial_system, current_state: :pending)
      machine.on :approve, pending: :approved
      machine.on :reject, pending: :rejected
      machine.lock

      machine.trigger(:approve)
      saved_state = machine.current_state
      assert_equal "approved", saved_state

      # Evolve the system but REMOVE the saved state
      # This is a potentially dangerous evolution
      incompatible_system = StateJacket::TransitionSystem.new
      incompatible_system.add pending: :processing  # Different transition
      incompatible_system.add processing: :completed
      incompatible_system.lock

      # Attempting to resume with an incompatible system that doesn't include the saved state
      assert_raises(ArgumentError) do
        StateJacket::StateMachine.new(incompatible_system, current_state: saved_state)
      end

      # A safer evolution would preserve existing states
      safe_evolved_system = StateJacket::TransitionSystem.new
      safe_evolved_system.add pending: [:processing, :rejected]
      safe_evolved_system.add processing: :completed
      safe_evolved_system.add approved: :completed  # Preserved the 'approved' state
      safe_evolved_system.lock

      # This works because the saved state exists in the evolved system
      resumed_machine = StateJacket::StateMachine.new(safe_evolved_system, current_state: saved_state)
      resumed_machine.on :complete, approved: :completed
      resumed_machine.lock

      assert_equal "approved", resumed_machine.current_state
      assert_equal ["complete"], resumed_machine.triggerable_events

      resumed_machine.trigger(:complete)
      assert_equal "completed", resumed_machine.current_state
    end

    def test_state_machine_evolution
      # Create a consistent transition system
      system = StateJacket::TransitionSystem.new
      system.add start: :in_progress
      system.add in_progress: [:review, :canceled]
      system.add review: [:approved, :rejected, :in_progress]  # Allow cyclic path back to in_progress
      system.add approved: :completed
      system.lock

      # Initial machine with simple event definitions
      initial_machine = StateJacket::StateMachine.new(system, current_state: :start)
      initial_machine.on :begin, start: :in_progress
      initial_machine.lock

      initial_machine.trigger(:begin)
      saved_state = initial_machine.current_state
      assert_equal "in_progress", saved_state

      # Evolve the state machine with different event names for the same transitions
      evolved_machine = StateJacket::StateMachine.new(system, current_state: saved_state)
      evolved_machine.on :submit_for_review, in_progress: :review   # New event name
      evolved_machine.on :abort, in_progress: :canceled             # New event name
      evolved_machine.lock

      # Can continue with new event names
      assert_equal "in_progress", evolved_machine.current_state
      assert_equal ["abort", "submit_for_review"], evolved_machine.triggerable_events.sort

      evolved_machine.trigger(:submit_for_review)
      assert_equal "review", evolved_machine.current_state

      # Further evolve with additional conditional paths
      final_machine = StateJacket::StateMachine.new(system, current_state: evolved_machine.current_state)
      final_machine.on :approve, review: :approved
      final_machine.on :reject, review: :rejected
      final_machine.on :revise, review: :in_progress  # Added cyclic transition not in original machine
      final_machine.lock

      assert_equal "review", final_machine.current_state
      assert_equal ["approve", "reject", "revise"], final_machine.triggerable_events.sort

      # Can use the new cyclic path
      final_machine.trigger(:revise)
      assert_equal "in_progress", final_machine.current_state

      # And continue with earlier defined events
      final_machine = StateJacket::StateMachine.new(system, current_state: final_machine.current_state)
      final_machine.on :submit_for_review, in_progress: :review
      final_machine.lock

      final_machine.trigger(:submit_for_review)
      assert_equal "review", final_machine.current_state
    end
  end

  class BasicWorkflowResumptionTest < Test
    def setup
      # Define a workflow transition system that might span multiple days or processes
      @system = StateJacket::TransitionSystem.new
      @system.add draft: :review
      @system.add review: [:approved, :rejected]
      @system.add approved: :published
      @system.lock
    end

    def test_basic_workflow_resumption
      # Start a workflow in one "process"
      machine1 = StateJacket::StateMachine.new(@system, current_state: :draft)
      machine1.on :submit, draft: :review
      machine1.on :approve, review: :approved
      machine1.on :reject, review: :rejected
      machine1.on :publish, approved: :published
      machine1.lock

      # Simulate the first step of the workflow
      machine1.trigger(:submit)
      assert_equal "review", machine1.current_state

      # Save state between "processes"
      saved_state = machine1.current_state

      # In a new "process", load the saved state and continue the workflow
      machine2 = StateJacket::StateMachine.new(@system, current_state: saved_state)
      machine2.on :approve, review: :approved
      machine2.on :reject, review: :rejected
      machine2.on :publish, approved: :published
      machine2.lock

      # Continue the workflow
      machine2.trigger(:approve)
      assert_equal "approved", machine2.current_state

      # Save state again
      saved_state = machine2.current_state

      # In a third "process", complete the workflow
      machine3 = StateJacket::StateMachine.new(@system, current_state: saved_state)
      machine3.on :publish, approved: :published
      machine3.lock

      machine3.trigger(:publish)
      assert_equal "published", machine3.current_state
      assert machine3.finished?
    end

    def test_resumption_with_different_transitions
      # Define a workflow in one process
      machine1 = StateJacket::StateMachine.new(@system, current_state: :draft)
      machine1.on :submit, draft: :review
      machine1.on :approve, review: :approved
      machine1.lock

      # Start the workflow
      machine1.trigger(:submit)
      assert_equal "review", machine1.current_state

      # Save state
      saved_state = machine1.current_state

      # In a new process, create a machine with different transitions
      # but still compatible with the workflow
      machine2 = StateJacket::StateMachine.new(@system, current_state: saved_state)
      machine2.on :reject, review: :rejected
      machine2.on :approve, review: :approved
      machine2.lock

      # Both events should be available since we're in the review state
      assert machine2.can_trigger?(:reject)
      assert machine2.can_trigger?(:approve)

      # Continue with a different path
      machine2.trigger(:reject)
      assert_equal "rejected", machine2.current_state
      assert machine2.finished?
    end
  end

  class ComplexWorkflowResumptionTest < Test
    def setup
      # Define a more complex workflow transition system
      @system = StateJacket::TransitionSystem.new
      @system.add application_submitted: [:under_review, :cancelled]
      @system.add under_review: [:pending_documents, :rejected, :approved]
      @system.add pending_documents: [:document_received, :expired]
      @system.add document_received: :under_review
      @system.add approved: [:active, :withdrawn]
      @system.add active: [:completed, :terminated]
      @system.lock
    end

    def test_multi_step_workflow_resumption
      # Initial setup and first step
      initial_machine = StateJacket::StateMachine.new(@system, current_state: :application_submitted)
      initial_machine.on :review, application_submitted: :under_review
      initial_machine.on :cancel, application_submitted: :cancelled
      initial_machine.lock

      initial_machine.trigger(:review)

      # Day 1: Review starts
      day1_machine = StateJacket::StateMachine.new(@system, current_state: initial_machine.current_state)
      day1_machine.on :request_documents, under_review: :pending_documents
      day1_machine.on :reject, under_review: :rejected
      day1_machine.on :approve, under_review: :approved
      day1_machine.lock

      day1_machine.trigger(:request_documents)
      assert_equal "pending_documents", day1_machine.current_state

      # Day 3: Documents received
      day3_machine = StateJacket::StateMachine.new(@system, current_state: day1_machine.current_state)
      day3_machine.on :receive, pending_documents: :document_received
      day3_machine.on :expire, pending_documents: :expired
      day3_machine.lock

      day3_machine.trigger(:receive)
      assert_equal "document_received", day3_machine.current_state

      # Day 5: Back to review
      day5_machine = StateJacket::StateMachine.new(@system, current_state: day3_machine.current_state)
      day5_machine.on :continue_review, document_received: :under_review
      day5_machine.lock

      day5_machine.trigger(:continue_review)
      assert_equal "under_review", day5_machine.current_state

      # Day 7: Approval
      day7_machine = StateJacket::StateMachine.new(@system, current_state: day5_machine.current_state)
      day7_machine.on :approve, under_review: :approved
      day7_machine.on :reject, under_review: :rejected
      day7_machine.lock

      day7_machine.trigger(:approve)
      assert_equal "approved", day7_machine.current_state

      # Day 10: Activation
      day10_machine = StateJacket::StateMachine.new(@system, current_state: day7_machine.current_state)
      day10_machine.on :activate, approved: :active
      day10_machine.on :withdraw, approved: :withdrawn
      day10_machine.lock

      day10_machine.trigger(:activate)
      assert_equal "active", day10_machine.current_state

      # Day 30: Completion
      day30_machine = StateJacket::StateMachine.new(@system, current_state: day10_machine.current_state)
      day30_machine.on :complete, active: :completed
      day30_machine.on :terminate, active: :terminated
      day30_machine.lock

      day30_machine.trigger(:complete)
      assert_equal "completed", day30_machine.current_state
      assert day30_machine.finished?
    end

    def test_serialize_and_deserialize_machine_state
      # Start workflow
      machine = StateJacket::StateMachine.new(@system, current_state: :application_submitted)
      machine.on :review, application_submitted: :under_review
      machine.on :request_documents, under_review: :pending_documents
      machine.on :receive, pending_documents: :document_received
      machine.on :continue_review, document_received: :under_review
      machine.on :approve, under_review: :approved
      machine.on :activate, approved: :active
      machine.on :complete, active: :completed
      machine.lock

      # Simulate progressing through workflow
      machine.trigger(:review)
      machine.trigger(:request_documents)

      # Serialize the machine state using to_hash (in a real app, this would go to a database)
      serialized_machine = machine.to_hash
      serialized_system = @system.to_hash

      # Later, deserialize and continue using from_hash
      system_restored = StateJacket::TransitionSystem.from_hash(serialized_system)
      resumed_machine = StateJacket::StateMachine.from_hash(system_restored, serialized_machine)

      # Verify state was properly restored
      assert_equal "pending_documents", resumed_machine.current_state
      assert_equal serialized_machine[:locked], resumed_machine.locked?
      assert_equal machine.rules.keys.sort, resumed_machine.rules.keys.sort

      # We need to define the events for the current state to continue
      resumed_machine = StateJacket::StateMachine.new(system_restored, current_state: resumed_machine.current_state)
      resumed_machine.on :receive, pending_documents: :document_received
      resumed_machine.on :continue_review, document_received: :under_review
      resumed_machine.on :expire, pending_documents: :expired
      resumed_machine.lock

      # Verify we can continue the workflow
      assert resumed_machine.can_trigger?(:receive)
      assert resumed_machine.can_trigger?(:expire)
      refute resumed_machine.can_trigger?(:review)

      # Continue workflow
      resumed_machine.trigger(:receive)
      assert_equal "document_received", resumed_machine.current_state
    end
  end

  class WorkflowRebuildingTest < Test
    def setup
      @system = StateJacket::TransitionSystem.new
      @system.add new: :preparation
      @system.add preparation: [:ready, :cancelled]
      @system.add ready: [:running, :cancelled]
      @system.add running: [:success, :failure]
      @system.lock
    end

    def test_rebuild_machine_from_state_and_valid_events
      # Original machine
      machine = StateJacket::StateMachine.new(@system, current_state: :new)
      machine.on :prepare, new: :preparation
      machine.on :finalize, preparation: :ready
      machine.on :cancel, [:preparation, :ready] => :cancelled
      machine.on :start, ready: :running
      machine.on :succeed, running: :success
      machine.on :fail, running: :failure
      machine.lock

      # Run first steps
      machine.trigger(:prepare)
      machine.trigger(:finalize)
      assert_equal "ready", machine.current_state

      # Serialize state for persistence
      state_data = {
        current_state: machine.current_state,
        system_states: @system.states,
        available_events: machine.triggerable_events
      }

      # Later, rebuild the machine from just the serialized state
      new_machine = StateJacket::StateMachine.new(@system, current_state: state_data[:current_state])

      # Only define the transitions that are relevant to the current state
      # and potential future states (in a real app, this might be loaded from configuration)
      new_machine.on :start, ready: :running
      new_machine.on :cancel, ready: :cancelled
      new_machine.on :succeed, running: :success
      new_machine.on :fail, running: :failure
      new_machine.lock

      # Verify correct restoration
      assert_equal "ready", new_machine.current_state
      assert_equal ["cancel", "start"], new_machine.triggerable_events.sort

      # Continue workflow
      new_machine.trigger(:start)
      assert_equal "running", new_machine.current_state
      assert_equal ["fail", "succeed"], new_machine.triggerable_events.sort
    end

    def test_resilient_to_event_redefinition
      # Define two machines with different event names but same state transitions
      machine1 = StateJacket::StateMachine.new(@system, current_state: :new)
      machine1.on :begin_prep, new: :preparation
      machine1.lock

      machine1.trigger(:begin_prep)
      current_state = machine1.current_state

      # Create a new machine with different event names
      machine2 = StateJacket::StateMachine.new(@system, current_state: current_state)
      machine2.on :complete, preparation: :ready
      machine2.on :abort, preparation: :cancelled
      machine2.lock

      # The events are different but the state machine continues working
      assert_equal "preparation", machine2.current_state
      assert machine2.can_trigger?(:complete)
      assert machine2.can_trigger?(:abort)

      machine2.trigger(:complete)
      assert_equal "ready", machine2.current_state
    end

    def test_transition_system_replacement
      # Start with one transition system
      original_system = StateJacket::TransitionSystem.new
      original_system.add new: :in_progress
      original_system.add in_progress: :completed
      original_system.lock

      # Use it for the initial part of workflow
      machine = StateJacket::StateMachine.new(original_system, current_state: :new)
      machine.on :start, new: :in_progress
      machine.lock

      machine.trigger(:start)
      saved_state = machine.current_state
      assert_equal "in_progress", saved_state

      # Create a completely different transition system with a compatible state
      # This could represent a major version upgrade of your application
      new_system = StateJacket::TransitionSystem.new
      new_system.add new: :initialized            # Different initial flow
      new_system.add initialized: :in_progress    # Different path to in_progress
      new_system.add in_progress: [:verified, :failed]  # Different options from in_progress
      new_system.add verified: :completed         # Different completion path
      new_system.add failed: :in_progress         # Recovery path
      new_system.lock

      # Can still resume with the new system as long as current_state exists
      resumed_machine = StateJacket::StateMachine.new(new_system, current_state: saved_state)
      resumed_machine.on :verify, in_progress: :verified
      resumed_machine.on :fail, in_progress: :failed
      resumed_machine.on :retry, failed: :in_progress
      resumed_machine.on :complete, verified: :completed
      resumed_machine.lock

      # Workflow can continue despite the completely different transition system
      assert_equal "in_progress", resumed_machine.current_state
      assert_equal ["fail", "verify"], resumed_machine.triggerable_events.sort

      # Can follow the new workflow paths
      resumed_machine.trigger(:verify)
      assert_equal "verified", resumed_machine.current_state

      resumed_machine.trigger(:complete)
      assert_equal "completed", resumed_machine.current_state
    end
  end

  # This test class examines safety measures and guidelines for system evolution
  class SafeEvolutionGuidanceTest < Test
    def test_safe_system_evolution_patterns
      # PATTERN 1: Additive Evolution (safest)
      # Original system
      original_system = StateJacket::TransitionSystem.new
      original_system.add submitted: [:approved, :rejected]
      original_system.lock

      # Initial machine and workflow
      machine = StateJacket::StateMachine.new(original_system, current_state: :submitted)
      machine.on :approve, submitted: :approved
      machine.on :reject, submitted: :rejected
      machine.lock

      machine.trigger(:approve)
      saved_state = machine.current_state

      # SAFE: Additive evolution - adds new states and transitions without changing existing ones
      additive_system = StateJacket::TransitionSystem.new
      additive_system.add submitted: [:approved, :rejected, :needs_info]  # Added new option
      additive_system.add approved: :completed                           # Extended existing state
      additive_system.add rejected: nil                                  # Kept as-is
      additive_system.add needs_info: :submitted                         # Added new state with path back
      additive_system.lock

      # Can safely resume
      additive_machine = StateJacket::StateMachine.new(additive_system, current_state: saved_state)
      additive_machine.on :complete, approved: :completed
      additive_machine.lock

      assert_equal "approved", additive_machine.current_state
      additive_machine.trigger(:complete)
      assert_equal "completed", additive_machine.current_state

      # PATTERN 2: Careful Replacement (more risky)
      # A replacement system that changes transition paths but preserves all states
      replacement_system = StateJacket::TransitionSystem.new
      replacement_system.add submitted: :under_review                   # Changed transition
      replacement_system.add under_review: [:approved, :rejected]       # New intermediate state
      replacement_system.add approved: [:completed, :revoked]           # Changed options
      replacement_system.add rejected: nil                              # Kept as-is
      replacement_system.lock

      # Can still resume but behavior might be different
      replacement_machine = StateJacket::StateMachine.new(replacement_system, current_state: saved_state)
      replacement_machine.on :complete, approved: :completed
      replacement_machine.on :revoke, approved: :revoked
      replacement_machine.lock

      assert_equal "approved", replacement_machine.current_state
      assert_equal ["complete", "revoke"], replacement_machine.triggerable_events.sort

      # PATTERN 3: State Renaming (potentially dangerous)
      # Using a compatibility mapping can help manage renamed states
      renamed_system = StateJacket::TransitionSystem.new
      renamed_system.add submitted: [:accepted, :declined]              # Renamed states
      renamed_system.add accepted: :finalized                           # Renamed state
      renamed_system.lock

      # State mapping for compatibility (would be in your migration code)
      state_mapping = {
        "approved" => "accepted",
        "rejected" => "declined"
      }

      # Map the old state to the new name before creating machine
      mapped_state = state_mapping[saved_state] || saved_state

      # Can resume with mapped state
      renamed_machine = StateJacket::StateMachine.new(renamed_system, current_state: mapped_state)
      renamed_machine.on :finalize, accepted: :finalized
      renamed_machine.lock

      assert_equal "accepted", renamed_machine.current_state
      assert_equal ["finalize"], renamed_machine.triggerable_events
    end
  end

  class FromHashSerializationTest < Test
    def test_transition_system_from_hash
      # Create original transition system
      original_system = StateJacket::TransitionSystem.new
      original_system.add draft: [:review, :canceled]
      original_system.add review: [:approved, :rejected]
      original_system.add approved: :published
      original_system.lock

      # Serialize to hash
      system_hash = original_system.to_hash

      # Rebuild from hash
      restored_system = StateJacket::TransitionSystem.from_hash(system_hash)

      # Verify restored system matches original
      assert restored_system.locked?
      assert_equal original_system.states.sort, restored_system.states.sort
      assert_equal original_system.transitioners.sort, restored_system.transitioners.sort
      assert_equal original_system.terminals.sort, restored_system.terminals.sort

      # Verify transitions work as expected
      assert restored_system.allows?(draft: :review)
      assert restored_system.allows?(review: :approved)
      assert restored_system.allows?(approved: :published)
      refute restored_system.allows?(draft: :published)
    end

    def test_state_machine_from_hash
      # Create original transition system and state machine
      system = StateJacket::TransitionSystem.new
      system.add start: :in_progress
      system.add in_progress: [:completed, :failed]
      system.lock

      original_machine = StateJacket::StateMachine.new(system, current_state: :start)
      original_machine.on :begin, start: :in_progress
      original_machine.on :complete, in_progress: :completed
      original_machine.on :fail, in_progress: :failed
      original_machine.lock

      # Serialize both to hashes
      system_hash = system.to_hash
      original_machine.to_hash

      # Trigger a transition and update the hash
      original_machine.trigger(:begin)
      machine_hash = original_machine.to_hash

      # Rebuild from hashes
      restored_system = StateJacket::TransitionSystem.from_hash(system_hash)
      restored_machine = StateJacket::StateMachine.from_hash(restored_system, machine_hash)

      # Verify restored machine matches original
      assert_equal original_machine.current_state, restored_machine.current_state
      assert_equal original_machine.locked?, restored_machine.locked?

      # Define the same events as the original machine to continue the workflow
      # Note: When from_h is used, it already restores the rules, but we need to verify
      # that state and behavior are correctly preserved
      assert_equal original_machine.rules.keys.sort, restored_machine.rules.keys.sort

      # Check if we can continue the workflow
      assert_equal "in_progress", restored_machine.current_state
      assert restored_machine.can_trigger?(:complete)
      assert restored_machine.can_trigger?(:fail)

      # Complete the workflow with the restored machine
      restored_machine.trigger(:complete)
      assert_equal "completed", restored_machine.current_state
      assert restored_machine.finished?
    end

    def test_complete_workflow_serialization_lifecycle
      # This test demonstrates a complete workflow with serialization at multiple points

      # 1. Define and initialize the workflow
      system = StateJacket::TransitionSystem.new
      system.add pending: [:approved, :rejected]
      system.add approved: :active
      system.add active: [:suspended, :completed]
      system.lock

      # Serialize the system for persistence
      system_hash = system.to_hash

      # 2. Start workflow - Day 1
      machine = StateJacket::StateMachine.new(system, current_state: :pending)
      machine.on :approve, pending: :approved
      machine.on :reject, pending: :rejected
      machine.lock

      # Serialize the initial machine state
      machine_hash_day1 = machine.to_hash

      # 3. Resume workflow - Day 2
      # Restore from saved hashes
      restored_system = StateJacket::TransitionSystem.from_hash(system_hash)
      day2_machine = StateJacket::StateMachine.from_hash(restored_system, machine_hash_day1)

      # Progress the workflow
      day2_machine.trigger(:approve)
      assert_equal "approved", day2_machine.current_state

      # Serialize for persistence again
      machine_hash_day2 = day2_machine.to_hash

      # 4. Resume workflow - Day 3
      # Restore from latest saved hash
      day3_machine = StateJacket::StateMachine.from_hash(restored_system, machine_hash_day2)

      # Define new events for current state (reusing the instance for clarity)
      day3_machine = StateJacket::StateMachine.new(restored_system, current_state: day3_machine.current_state)
      day3_machine.on :activate, approved: :active
      day3_machine.lock

      # Progress the workflow
      day3_machine.trigger(:activate)
      assert_equal "active", day3_machine.current_state

      # Serialize for persistence again
      machine_hash_day3 = day3_machine.to_hash

      # 5. Resume workflow - Day 4
      # Restore from latest saved hash
      day4_machine = StateJacket::StateMachine.from_hash(restored_system, machine_hash_day3)

      # Define new events for current state (reusing the instance for clarity)
      day4_machine = StateJacket::StateMachine.new(restored_system, current_state: day4_machine.current_state)
      day4_machine.on :suspend, active: :suspended
      day4_machine.on :complete, active: :completed
      day4_machine.lock

      # Complete the workflow
      day4_machine.trigger(:complete)
      assert_equal "completed", day4_machine.current_state
      assert day4_machine.finished?

      # Final serialization
      final_machine_hash = day4_machine.to_hash

      # Verify we can still restore from the final state
      final_machine = StateJacket::StateMachine.from_hash(restored_system, final_machine_hash)
      assert_equal "completed", final_machine.current_state
      assert final_machine.finished?
    end
  end
end
