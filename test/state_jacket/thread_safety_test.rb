# frozen_string_literal: true

require_relative "../test_helper"

module StateJacket
  class ThreadSafetyTest < Minitest::Test
    def setup
      # Create a simple workflow with 4 states
      @matrix = Matrix.new
      @matrix.add(:draft)
      @matrix.add(:reviewing)
      @matrix.add(:approved)
      @matrix.add(:published)
      @matrix.add(draft: :reviewing)
      @matrix.add(reviewing: [:approved, :draft])
      @matrix.add(approved: :published)
    end

    # Helper to create a fresh copy of the standard matrix
    def create_matrix
      matrix = Matrix.new
      matrix.add(:draft)
      matrix.add(:reviewing)
      matrix.add(:approved)
      matrix.add(:published)
      matrix.add(draft: :reviewing)
      matrix.add(reviewing: [:approved, :draft])
      matrix.add(approved: :published)
      matrix
    end

    # Helper to create a standard machine for testing
    def create_machine(matrix)
      machine = Machine.new(matrix, current_state: :draft)
      machine.on(:submit, draft: :reviewing)
      machine.on(:revise, reviewing: :draft)
      machine.on(:approve, reviewing: :approved)
      machine.on(:publish, approved: :published)
      machine
    end

    def test_matrix_concurrent_modifications
      matrix = Matrix.new

      # Create multiple threads that modify the matrix concurrently
      # Each thread adds unique states with no overlaps
      threads = 10.times.map do |i|
        Thread.new do
          # Add states and transitions with thread-specific prefixes
          prefix = "thread_#{i}_"
          matrix.add("#{prefix}state_1")
          matrix.add("#{prefix}state_2")
          matrix.add("#{prefix}state_3")
          matrix.add("#{prefix}state_1" => "#{prefix}state_2")
          matrix.add("#{prefix}state_2" => "#{prefix}state_3")
        end
      end

      threads.each(&:join)

      # Verify matrix integrity - each thread adds 3 states
      expected_states = 30 # 10 threads × 3 states each
      assert_equal expected_states, matrix.states.size
      matrix.lock
      assert matrix.locked?
    end

    def test_matrix_locked_thread_safety
      matrix = create_matrix

      # Lock the matrix
      matrix.lock

      # Track lock attempts for atomicity verification
      lock_count = 0

      # Create threads that try to modify the locked matrix and perform locks
      threads = 10.times.map do
        Thread.new do
          # Try to add a state to the locked matrix
          begin
            matrix.add(:new_state)
            flunk "Should not be able to add state after locking"
          rescue StateJacket::Matrix::Error
            # Expected in concurrent scenario
          end

          # Also try to lock the matrix again (should be idempotent)
          matrix.lock
          lock_count += 1

          # Test concurrent reads from locked matrix
          assert_equal 4, matrix.states.size
          assert_includes matrix.states, "draft"
          assert_includes matrix.transitioners, "reviewing"
          assert_includes matrix.terminals, "published"
          assert matrix.allows?(draft: :reviewing)
        end
      end

      threads.each(&:join)

      # All threads should have executed lock without error
      assert_equal 10, lock_count
      assert matrix.locked?
    end

    # test_matrix_concurrent_reads removed - functionality covered by test_matrix_cache_consistency

    def test_machine_concurrent_event_definition
      matrix = create_matrix
      matrix.lock

      machine = Machine.new(matrix, current_state: :draft)

      # Define events concurrently (different and same events)
      threads = 10.times.map do |i|
        Thread.new do
          case i % 5
          when 0
            machine.on(:submit, draft: :reviewing)
          when 1
            machine.on(:revise, reviewing: :draft)
          when 2
            machine.on(:approve, reviewing: :approved)
            machine.on(:publish, approved: :published)
          when 3
            # Same event with same transition (should be idempotent)
            machine.on(:submit, draft: :reviewing)
          when 4
            # Same event with different transition (should be additive)
            machine.on(:approve, reviewing: :approved)
          end
        end
      end

      threads.each(&:join)

      # Lock the machine after concurrent definition
      machine.lock

      # Verify all events were defined correctly
      assert_includes machine.events, "submit"
      assert_includes machine.events, "revise"
      assert_includes machine.events, "approve"
      assert_includes machine.events, "publish"

      # Verify event rules
      rules = machine.rules

      # Check submit rule
      submit_rules = rules["submit"]
      assert_equal 1, submit_rules.count
      assert_equal "reviewing", submit_rules.first["draft"]

      # Check approve rule
      approve_rules = rules["approve"]
      assert_equal 1, approve_rules.count
      assert_equal "approved", approve_rules.first["reviewing"]
    end

    def test_machine_concurrent_transition_triggering
      matrix = create_matrix
      matrix.lock

      machine = Machine.new(matrix, current_state: :draft)
      machine.on(:submit, draft: :reviewing)
      machine.on(:revise, reviewing: :draft)
      machine.on(:approve, reviewing: :approved)
      machine.on(:publish, approved: :published)
      machine.lock

      # Track transition count
      transition_count = 0
      mutex = Mutex.new

      # Create threads that try to trigger transitions
      threads = 10.times.map do
        Thread.new do
          # Try to trigger events based on current state
          if machine.can_trigger?(:submit)
            result = machine.trigger(:submit) do |from, to|
              mutex.synchronize { transition_count += 1 }
            end
            assert result.successful? if result
          end

          sleep(0.001) # Small delay to allow state to potentially change

          if machine.can_trigger?(:revise)
            result = machine.trigger(:revise) do |from, to|
              mutex.synchronize { transition_count += 1 }
            end
            assert result.successful? if result
          end

          if machine.can_trigger?(:approve)
            result = machine.trigger(:approve) do |from, to|
              mutex.synchronize { transition_count += 1 }
            end
            assert result.successful? if result
          end
        rescue ArgumentError
          # Expected in concurrent scenario
        end
      end

      threads.each(&:join)

      # Verify machine is in a valid state
      assert_includes ["draft", "reviewing", "approved"], machine.current_state

      # Verify we had appropriate number of transitions
      # At most 3 successful transitions are possible in this scenario
      assert_operator transition_count, :<=, 3
    end

    def test_machine_concurrent_reads
      matrix = create_matrix
      matrix.lock

      machine = Machine.new(matrix, current_state: :draft)
      machine.on(:submit, draft: :reviewing)
      machine.on(:revise, reviewing: :draft)
      machine.on(:approve, reviewing: :approved)
      machine.lock

      results = []
      threads = []

      10.times do
        threads << Thread.new do
          20.times do
            results << [
              machine.current_state,
              machine.finished?,
              machine.events.sort,
              machine.triggerable_events,
              machine.reachable_states
            ]
          end
        end
      end

      threads.each(&:join)

      # All results should be identical
      expected = [
        "draft",
        false,
        ["approve", "revise", "submit"].sort,
        ["submit"],
        ["reviewing"]
      ]

      results.each do |result|
        assert_equal expected, result
      end
    end

    def test_concurrent_serialization_and_deserialization
      matrix = create_matrix
      matrix.lock

      machine = Machine.new(matrix, current_state: :draft)
      machine.on(:submit, draft: :reviewing)
      machine.on(:approve, reviewing: :approved)
      machine.lock

      # Capture serialized representation
      matrix_hash = matrix.to_hash
      machine_hash = machine.to_hash

      threads = []
      created_objects = []
      mutex = Mutex.new

      5.times do
        threads << Thread.new do
          10.times do
            # Create new objects from hash concurrently
            new_matrix = Matrix.from_hash(matrix_hash)
            new_machine = Machine.from_hash(new_matrix, machine_hash)

            # Verify basic properties before adding to collection
            assert new_matrix.locked?
            assert_equal 4, new_matrix.states.size
            assert new_machine.locked?
            assert_equal "draft", new_machine.current_state

            # Store created objects
            mutex.synchronize do
              created_objects << [new_matrix, new_machine]
            end
          end
        end
      end

      threads.each(&:join)

      # Verify all objects were created correctly
      assert_equal 50, created_objects.size
      created_objects.each do |created_matrix, created_machine|
        assert_equal matrix_hash, created_matrix.to_hash
        assert_equal machine_hash, created_machine.to_hash
      end
    end

    def test_matrix_cache_consistency
      # Test that cached values remain consistent under concurrent access
      matrix = create_matrix
      matrix.lock

      threads = []
      results = []
      mutex = Mutex.new

      20.times do
        threads << Thread.new do
          50.times do
            # Perform multiple reads that should use cached values
            states = matrix.states
            terminals = matrix.terminals
            transitioners = matrix.transitioners

            # Store results for later verification
            mutex.synchronize do
              results << {
                states: states.sort,
                terminals: terminals.sort,
                transitioners: transitioners.sort,
                sum_check: states.size == terminals.size + transitioners.size,
                # Also test other read methods for comprehensive coverage
                include_draft: matrix.include?("draft"),
                terminal_published: matrix.terminal?("published"),
                transitioner_reviewing: matrix.transitioner?("reviewing"),
                allows_transition: matrix.allows?(draft: :reviewing)
              }
            end
          end
        end
      end

      threads.each(&:join)

      # Verify cache consistency
      expected_states = ["draft", "reviewing", "approved", "published"].sort
      expected_terminals = ["published"].sort
      expected_transitioners = ["draft", "reviewing", "approved"].sort

      results.each do |result|
        assert_equal expected_states, result[:states]
        assert_equal expected_terminals, result[:terminals]
        assert_equal expected_transitioners, result[:transitioners]
        assert result[:sum_check], "Sum of terminals and transitioners should equal total states"

        # Verify other read operations
        assert result[:include_draft], "Should include draft state"
        assert result[:terminal_published], "Published should be terminal"
        assert result[:transitioner_reviewing], "Reviewing should be transitioner"
        assert result[:allows_transition], "Should allow draft to reviewing transition"
      end
    end

    def test_matrix_concurrent_rule_modification
      # Test handling of multiple threads modifying the same rule
      matrix = Matrix.new
      matrix.add(:state1)
      matrix.add(:state2)
      matrix.add(:state3)
      matrix.add(:state4)

      # Create threads that all try to modify the same transitions
      threads = 10.times.map do
        Thread.new do
          # Add transitions for the same states
          matrix.add(state1: :state2)
          matrix.add(state1: :state3)
          matrix.add(state1: :state4)
          matrix.add(state2: [:state3, :state4])
        end
      end

      threads.each(&:join)

      # Verify the rules are correctly merged without duplication
      # State1 should transition to state2, state3, and state4
      targets = matrix.rules["state1"]
      assert_equal 3, targets.size
      assert_includes targets, "state2"
      assert_includes targets, "state3"
      assert_includes targets, "state4"

      # State2 should transition to state3 and state4
      targets = matrix.rules["state2"]
      assert_equal 2, targets.size
      assert_includes targets, "state3"
      assert_includes targets, "state4"
    end

    # test_exclusive_state_transitions removed - functionality covered by test_state_change_atomicity

    def test_no_deadlocks_with_nested_calls
      # Test that methods calling other synchronized methods don't deadlock
      matrix = create_matrix
      matrix.lock

      machine = create_machine(matrix)
      machine.lock

      threads = []

      # Create threads that make nested synchronized calls
      5.times do
        threads << Thread.new do
          100.times do
            # These calls internally invoke other synchronized methods
            machine.finished?                # Calls matrix.terminal?(current_state)
            machine.can_trigger?(:submit)    # Uses cache that requires synchronization
            machine.triggerable_events       # Makes multiple synchronized calls
            machine.reachable_states         # Makes multiple synchronized calls

            # Add a read of matrix properties that uses caching
            assert_equal 4, matrix.states.size
            assert_equal 1, matrix.terminals.size
            assert_equal 3, matrix.transitioners.size
          end
        end
      end

      # Use a timeout to detect potential deadlocks
      threads.each { |t| t.join(2) }

      # Verify all threads completed (no deadlocks)
      threads.each do |t|
        refute t.alive?, "Thread should have completed (deadlock detected)"
      end
    end

    def test_state_change_atomicity
      # Test that state changes are atomic and exclusive
      matrix = create_matrix
      matrix.lock

      # Part 1: Test exclusive transitions (only one thread succeeds)
      machine = create_machine(matrix)
      machine.lock

      # Track successful transitions
      successful_transitions = []
      mutex = Mutex.new

      # Have multiple threads try to transition from draft to reviewing
      threads = 10.times.map do |i|
        Thread.new do
          if machine.can_trigger?(:submit)
            result = machine.trigger(:submit) do |from, to|
              # This block should only execute for the first successful thread
              mutex.synchronize do
                successful_transitions << {thread: i, from: from, to: to}
              end
            end

            if result.successful?
              # Record successful transition
              mutex.synchronize do
                successful_transitions << {thread: i, event: :submit, success: true}
              end
            end
          end
        end
      end

      threads.each(&:join)

      # Verify that exactly one thread successfully transitioned
      assert_equal 1, successful_transitions.count { |t| t[:success] }
      assert_equal "reviewing", machine.current_state

      # Part 2: Test atomicity across multiple machines
      # Create multiple machines at different states
      machines = [
        create_machine(matrix).tap { |m| m.lock },
        create_machine(matrix).tap { |m|
          m.lock
          m.trigger(:submit)  # Now in reviewing state
        },
        create_machine(matrix).tap { |m|
          m.lock
          m.trigger(:submit)  # Now in reviewing state
        }
      ]

      # Define the events to trigger for each machine
      machine_events = [
        [:submit],           # draft -> reviewing
        [:approve],          # reviewing -> approved
        [:revise, :approve]  # reviewing -> draft -> approved (needs 2 triggers)
      ]

      # Track transition results
      results = []
      mutex = Mutex.new

      # Create threads to trigger transitions on different machines simultaneously
      threads = machines.each_with_index.map do |machine, i|
        Thread.new do
          events = machine_events[i]

          events.each do |event|
            if machine.can_trigger?(event)
              current_before = machine.current_state
              result = machine.trigger(event)
              current_after = machine.current_state

              # Track the result
              mutex.synchronize do
                results << {
                  machine: i,
                  event: event,
                  success: result.successful?,
                  from: current_before,
                  to: current_after,
                  consistent: result.from == current_before &&
                    result.to == current_after &&
                    (result.successful? ? result.to : result.from) == current_after
                }
              end
            end
          rescue ArgumentError
            # Expected in concurrent scenario
          end
        end
      end

      threads.each(&:join)

      # Verify all transitions were atomic (from/to states match actual machine states)
      results.each do |result|
        assert result[:consistent],
          "State transition wasn't atomic: machine #{result[:machine]}, " \
            "event: #{result[:event]}, from: #{result[:from]}, to: #{result[:to]}"
      end
    end

    def test_check_trigger_race_condition
      # Test for race conditions between checking if an event can be triggered and triggering it
      matrix = create_matrix
      matrix.lock

      machine = create_machine(matrix)
      machine.lock

      # Create a shared flag to control execution order
      can_proceed = false
      mutex = Mutex.new
      cv = ConditionVariable.new

      # Thread 1: Check if can trigger and wait before triggering
      thread1 = Thread.new do
        # First check if the event can be triggered
        can_trigger = machine.can_trigger?(:submit)
        assert can_trigger, "Should be able to trigger submit from draft state"

        # Signal we've checked and wait for go-ahead
        mutex.synchronize do
          can_proceed = true
          cv.signal
          # Wait for thread2 to potentially change state
          sleep 0.1
        end

        # Now try to trigger - this should still work since we're synchronized
        begin
          result = machine.trigger(:submit)
          assert result.successful?, "First thread should successfully trigger event"
          assert_equal "reviewing", machine.current_state
        rescue ArgumentError => e
          flunk "First thread shouldn't fail: #{e.message}"
        end
      end

      # Thread 2: Wait for thread1 to check, then try to trigger first
      thread2 = Thread.new do
        # Wait for thread1 to check
        mutex.synchronize do
          until can_proceed
            cv.wait(mutex)
          end
        end

        # Try to trigger the same event
        begin
          machine.trigger(:submit)
          flunk "Second thread should not succeed since first thread holds lock"
        rescue StateJacket::Machine::Error
          # Expected - either the lock prevents this or state has changed
        end
      end

      thread1.join
      thread2.join

      # Verify final state
      assert_equal "reviewing", machine.current_state
    end

    def test_callback_thread_safety
      # Test thread safety with callback blocks during transitions
      matrix = create_matrix
      matrix.lock

      machine = create_machine(matrix)
      machine.lock

      # Create a shared resource to simulate external state modification
      shared_counter = 0
      Mutex.new

      # Create multiple threads that trigger transitions with callbacks
      threads = 10.times.map do
        Thread.new do
          if machine.current_state == "draft" && machine.can_trigger?(:submit)
            # Trigger with a callback that accesses shared state
            machine.trigger(:submit) do |from, to|
              # This block should execute atomically
              current_value = shared_counter
              # Simulate some work
              sleep(rand(0.001..0.005))
              # Increment counter
              shared_counter = current_value + 1
            end
          end
        end
      end

      threads.each(&:join)

      # Only one thread should have successfully transitioned and incremented
      assert_equal "reviewing", machine.current_state
      assert_equal 1, shared_counter, "Only one callback should have executed"
    end

    # test_matrix_lock_race_condition removed - functionality covered by test_matrix_locked_thread_safety

    # test_event_name_collision removed - functionality covered by test_machine_concurrent_event_definition

    def test_partial_initialization_safety
      # Test thread safety during initialization phase
      # Create threads that each try to create and initialize their own matrix
      matrices = []

      threads = 10.times.map do |i|
        Thread.new do
          # Create a new matrix and immediately start adding states/transitions
          matrix = Matrix.new

          # Add states with thread-specific names
          prefix = "t#{i}_"
          matrix.add("#{prefix}draft")
          matrix.add("#{prefix}reviewing")

          # Add transitions
          matrix.add("#{prefix}draft" => "#{prefix}reviewing")

          # Store matrix for later verification
          matrices << matrix
        end
      end

      threads.each(&:join)

      # Verify each matrix has its own independent state
      matrices.each_with_index do |matrix, i|
        prefix = "t#{i}_"

        # Each matrix should have exactly 2 states
        assert_equal 2, matrix.states.size

        # States should have the correct prefix
        assert_includes matrix.states, "#{prefix}draft"
        assert_includes matrix.states, "#{prefix}reviewing"

        # Transitions should work correctly
        assert matrix.allows?("#{prefix}draft" => "#{prefix}reviewing")
      end
    end
  end
end
