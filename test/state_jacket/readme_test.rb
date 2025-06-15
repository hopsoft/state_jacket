# frozen_string_literal: true

require "test_helper"

class StateJacket::ReadmeTest < Minitest::Test
  def test_getting_started
    # Define the state transition rules (from README Getting Started section)
    matrix = StateJacket::Matrix.new
    matrix.add created: :submitted
    matrix.add submitted: [:approved, :rejected]
    matrix.add approved: :published

    # Access transitions before locking (convenient for machine setup)
    assert_equal({"created" => "submitted"}, matrix[:created_to_submitted])
    expected_keys = [:created_to_submitted, :submitted_to_approved, :submitted_to_rejected, :approved_to_published]
    assert_equal expected_keys.sort, matrix.transition_keys.sort

    matrix.lock
    hash = matrix.to_h

    expected_hash = {
      locked: true,
      states: ["created", "submitted", "approved", "rejected", "published"],
      transitioners: ["created", "submitted", "approved"],
      terminals: ["rejected", "published"],
      rules: {
        "created" => ["submitted"],
        "submitted" => ["approved", "rejected"],
        "approved" => ["published"],
        "rejected" => nil,
        "published" => nil
      },
      transitions: {
        created_to_submitted: {"created" => "submitted"},
        submitted_to_approved: {"submitted" => "approved"},
        submitted_to_rejected: {"submitted" => "rejected"},
        approved_to_published: {"approved" => "published"}
      }
    }

    assert_equal expected_hash, hash

    # Create a state machine using the matrix
    machine = StateJacket::Machine.new(matrix, current_state: :created)

    # Use transition helpers for cleaner event definitions
    machine.on :submit, matrix[:created_to_submitted]
    machine.on :approve, matrix[:submitted_to_approved]
    machine.on :reject, matrix[:submitted_to_rejected]
    machine.on :publish, matrix[:approved_to_published]

    machine.lock
    machine_hash = machine.to_h

    expected_machine_hash = {
      locked: true,
      current_state: "created",
      finished: false,
      reachable_states: ["submitted"],
      triggerable_events: ["submit"],
      rules: {
        "submit" => [{"created" => "submitted"}],
        "approve" => [{"submitted" => "approved"}],
        "reject" => [{"submitted" => "rejected"}],
        "publish" => [{"approved" => "published"}]
      }
    }

    assert_equal expected_machine_hash, machine_hash
  end

  def test_transition_helpers
    # Test Transition Helpers section examples from README
    matrix = StateJacket::Matrix.new

    # Access transitions by key
    matrix.add created: :submitted
    assert_equal({"created" => "submitted"}, matrix[:created_to_submitted])

    # List all available transitions
    matrix.add submitted: [:approved, :rejected]
    expected_keys = [:created_to_submitted, :submitted_to_approved, :submitted_to_rejected]
    assert_equal expected_keys.sort, matrix.transition_keys.sort

    # Works even before locking (returns frozen copies)
    unlocked_matrix = StateJacket::Matrix.new
    unlocked_matrix.add created: :published
    transition = unlocked_matrix[:created_to_published]
    assert_equal({"created" => "published"}, transition)
    assert transition.frozen?

    # Test machine setup with transition helpers (from README example)
    matrix.lock
    machine = StateJacket::Machine.new(matrix, current_state: :created)
    # Use transition helpers for cleaner event definitions (from README)
    machine.on :submit, matrix[:created_to_submitted]
    machine.on :approve, matrix[:submitted_to_approved]
    machine.on :reject, matrix[:submitted_to_rejected]
    machine.lock

    # Verify transition helpers work in machine context
    assert machine.can_trigger?(:submit)
    result = machine.trigger(:submit)
    assert result.successful?
    assert_equal "submitted", machine.current_state
  end

  def test_data_immutability
    # Test Data Immutability section examples from README
    matrix = StateJacket::Matrix.new
    matrix.add created: :submitted
    matrix.lock

    # All data returned by introspection methods is frozen to prevent accidental modification
    states = matrix.states
    assert states.frozen?     # => true
    assert_raises(FrozenError) { states << "archived" } # => FrozenError

    rules = matrix.rules
    assert_raises(FrozenError) { rules["created"] = ["archived"] }  # => FrozenError
    assert_raises(FrozenError) { rules["created"] << "archived" }   # => FrozenError
  end

  def test_thread_safety
    matrix = StateJacket::Matrix.new
    matrix.add submitted: :approved
    matrix.lock

    machine = StateJacket::Machine.new(matrix, current_state: :submitted)
    machine.on :approve, matrix[:submitted_to_approved]
    machine.lock

    # Safe to use across multiple threads
    threads = 10.times.map do
      Thread.new do
        machine.trigger(:approve) if machine.can_trigger?(:approve)
      end
    end
    threads.each(&:join)

    # Only one thread should have succeeded
    assert_equal "approved", machine.current_state
  end

  def test_introspection
    matrix = StateJacket::Matrix.new
    matrix.add created: :submitted     # submitted for review
    matrix.add submitted: [:approved, :rejected]
    matrix.add approved: :published
    matrix.lock

    # Matrix introspection
    assert_includes matrix.states, "created"           # All states
    assert_includes matrix.transitioners, "created"    # States with outgoing transitions
    assert_includes matrix.terminals, "rejected"       # States with no outgoing transitions
    assert matrix.include?(:created)                   # Check if state exists

    machine = StateJacket::Machine.new(matrix, current_state: :created)
    machine.on :submit, matrix[:created_to_submitted]
    machine.on :approve, matrix[:submitted_to_approved]
    machine.on :reject, matrix[:submitted_to_rejected]
    machine.on :publish, matrix[:approved_to_published]
    machine.lock

    # Machine introspection
    assert_equal "created", machine.current_state         # Current state
    assert !machine.finished?                            # Is in terminal state?
    assert machine.can_trigger?(:submit)                 # Can event be triggered?
    assert_includes machine.triggerable_events, "submit" # All events that can be triggered now
    assert_includes machine.reachable_states, "submitted" # States reachable from current state
  end

  def test_pattern_matching
    matrix = StateJacket::Matrix.new
    matrix.add created: :submitted     # submitted for review
    matrix.add submitted: [:approved, :rejected]
    matrix.add approved: :published
    matrix.lock

    machine = StateJacket::Machine.new(matrix, current_state: :submitted)
    machine.on :submit, matrix[:created_to_submitted]
    machine.on :approve, matrix[:submitted_to_approved]
    machine.on :reject, matrix[:submitted_to_rejected]
    machine.on :publish, matrix[:approved_to_published]
    machine.lock

    result = case machine
    in current_state: "submitted", triggerable_events: [*, "approve", *]
      "Can approve!"
    in finished: true
      "Workflow complete"
    else
      "Keep going..."
    end

    assert_equal "Can approve!", result
  end

  def test_workflow_section
    # Test the Workflow section examples from README
    matrix = StateJacket::Matrix.new
    matrix.add created: :submitted
    matrix.add submitted: [:approved, :rejected]
    matrix.add approved: :published
    matrix.lock

    machine = StateJacket::Machine.new(matrix, current_state: :submitted)
    machine.on :submit, matrix[:created_to_submitted]
    machine.on :approve, matrix[:submitted_to_approved]
    machine.on :reject, matrix[:submitted_to_rejected]
    machine.on :publish, matrix[:approved_to_published]
    machine.lock

    # Test workflow trigger with business logic block
    callback_executed = false
    result = machine.trigger(:approve) do |from, to|
      # Simulate business logic from README example
      callback_executed = true
      assert_equal "submitted", from
      assert_equal "approved", to
      # Would normally do: update_database_timestamp, etc.
    end

    assert callback_executed
    assert result.successful?
    assert_equal "submitted", result.from
    assert_equal "approved", result.to
    assert_equal "approved", machine.current_state

    # Test traditional result checking pattern from README
    success_handled = false
    if result.successful?
      success_handled = true
      assert_equal "submitted", result.from
      assert_equal "approved", result.to
      assert_equal "approved", machine.current_state
      # Would normally do: send_notification_to_author, redirect_to_approval_dashboard
    else
      flunk "Result should be successful"
    end
    assert success_handled

    # Test pattern matching from README
    pattern_matched = false
    case result
    in status: :ok, to: "approved"
      pattern_matched = true
      # Would normally do: send_notification_to_author, redirect_to_approval_dashboard
    in status: :error, error: StateJacket::Machine::Error => e
      flunk "Should not match StateJacket error pattern: #{e.message}"
    in status: :error, error: StandardError => e
      flunk "Should not match error pattern: #{e.message}"
    end
    assert pattern_matched
  end

  def test_workflow_error_handling
    # Test error handling in workflow blocks
    matrix = StateJacket::Matrix.new
    matrix.add submitted: :approved
    matrix.lock

    machine = StateJacket::Machine.new(matrix, current_state: :submitted)
    machine.on :approve, matrix[:submitted_to_approved]
    machine.lock

    # Test error in business logic block
    result = machine.trigger(:approve) do |from, to|
      raise "Reviewer not authorized"
    end

    refute result.successful?
    assert_equal :error, result.status
    assert_equal "Reviewer not authorized", result.error.message
    assert_equal "submitted", machine.current_state  # State unchanged on error

    # Test error handling with pattern matching
    pattern_matched = false
    case result
    in status: :ok, to: "approved"
      flunk "Should not match success pattern"
    in status: :error, error: StateJacket::Machine::Error => e
      flunk "Should not match StateJacket error pattern: #{e.message}"
    in status: :error, error: StandardError => e
      pattern_matched = true
      assert_equal "Reviewer not authorized", e.message
    end
    assert pattern_matched
  end

  def test_workflow_persistence
    # Test workflow persistence examples from README
    matrix = StateJacket::Matrix.new
    matrix.add created: :submitted
    matrix.add submitted: [:approved, :rejected]
    matrix.add approved: :published
    matrix.lock

    machine = StateJacket::Machine.new(matrix, current_state: :created)
    machine.on :submit, matrix[:created_to_submitted]
    machine.on :approve, matrix[:submitted_to_approved]
    machine.on :reject, matrix[:submitted_to_rejected]
    machine.on :publish, matrix[:approved_to_published]
    machine.lock

    # Save state (from README example)
    data = {
      matrix: matrix.to_h,
      machine: machine.to_h
    }
    # In real app: File.write("workflow.json", JSON.dump(data))

    # Restore later (from README example)
    # In real app: data = JSON.parse(File.read("workflow.json"), symbolize_names: true)
    restored_matrix = StateJacket::Matrix.from_hash(data[:matrix])
    restored_machine = StateJacket::Machine.from_hash(restored_matrix, data[:machine])

    assert_equal machine.current_state, restored_machine.current_state
    assert_equal machine.triggerable_events, restored_machine.triggerable_events
    assert_equal machine.reachable_states, restored_machine.reachable_states
  end

  def test_evolving_workflows
    # Test evolving workflows example from README
    # Original workflow
    original_matrix = StateJacket::Matrix.new
    original_matrix.add created: :submitted
    original_matrix.add submitted: [:approved, :rejected]
    original_matrix.add approved: :published
    original_matrix.lock

    machine = StateJacket::Machine.new(original_matrix, current_state: :published)
    machine.on :submit, original_matrix[:created_to_submitted]
    machine.on :approve, original_matrix[:submitted_to_approved]
    machine.on :reject, original_matrix[:submitted_to_rejected]
    machine.on :publish, original_matrix[:approved_to_published]
    machine.lock

    # Save current state to simulate file persistence
    workflow_data = {matrix: original_matrix.to_h, machine: machine.to_h}
    # In real app: File.write("workflow.json", JSON.dump(workflow_data))

    # Later: Business requires archiving capability
    # Load saved workflow data (simulate JSON.parse)
    saved_data = workflow_data  # Simulate: JSON.parse(File.read("workflow.json"), symbolize_names: true)

    # Start from the original matrix definition (excluding locked state)
    evolved_matrix = StateJacket::Matrix.from_hash(saved_data[:matrix].except(:locked))

    # Add new archiving transitions using shorthand syntax
    evolved_matrix.add [:created, :rejected, :published] => :archived
    evolved_matrix.lock

    # Test evolved matrix structure
    expected_evolved_states = ["created", "submitted", "approved", "rejected", "published", "archived"]
    assert_equal expected_evolved_states.sort, evolved_matrix.states.sort

    expected_evolved_transitioners = ["created", "submitted", "approved", "rejected", "published"]
    assert_equal expected_evolved_transitioners.sort, evolved_matrix.transitioners.sort

    assert_equal ["archived"], evolved_matrix.terminals

    # Test evolved rules
    evolved_rules = evolved_matrix.rules
    assert_equal ["submitted", "archived"].sort, evolved_rules["created"].sort
    assert_equal ["approved", "rejected"].sort, evolved_rules["submitted"].sort
    assert_equal ["published"], evolved_rules["approved"]
    assert_equal ["archived"], evolved_rules["rejected"]
    assert_equal ["archived"], evolved_rules["published"]
    assert_nil evolved_rules["archived"]

    # Resume workflow with evolved system using saved machine definition
    resumed_machine = StateJacket::Machine.from_hash(evolved_matrix, saved_data[:machine].except(:locked))

    # Add new archive event using shorthand syntax
    resumed_machine.on :archive, [:created, :rejected, :published] => :archived
    resumed_machine.lock

    # Test evolved machine capabilities
    assert_equal "published", resumed_machine.current_state
    refute resumed_machine.finished?
    assert_equal ["archived"], resumed_machine.reachable_states
    assert_equal ["archive"], resumed_machine.triggerable_events

    # Test evolved machine rules
    resumed_rules = resumed_machine.rules
    expected_archive_rules = [
      {"created" => "archived"},
      {"rejected" => "archived"},
      {"published" => "archived"}
    ]
    assert_equal expected_archive_rules.sort_by(&:to_s), resumed_rules["archive"].sort_by(&:to_s)

    # Now the workflow supports archiving from its current :published state
    assert resumed_machine.can_trigger?(:archive)

    callback_executed = false
    result = resumed_machine.trigger(:archive) do |from, to|
      callback_executed = true
      assert_equal "published", from
      assert_equal "archived", to
      # Would normally: Send notifications, update database, audit log, etc.
    end

    assert callback_executed
    assert result.successful?
    assert_equal "archived", resumed_machine.current_state
  end

  def test_event_syntax_styles
    # Test alternative syntax styles from Key Features section
    matrix = StateJacket::Matrix.new
    matrix.add [:approved, :created] => :published
    matrix.add [:submitted, :approved] => :rejected
    matrix.add :published
    matrix.add :rejected
    matrix.lock

    machine = StateJacket::Machine.new(matrix, current_state: :created)

    # Alternative syntax (shorthand) from README
    machine.on :publish, [:approved, :created] => :published
    machine.on :reject, [:submitted, :approved] => :rejected

    # Alternative syntax (verbose) from README
    machine.on :publish_verbose, {approved: :published, created: :published}
    machine.on :reject_verbose, {submitted: :rejected, approved: :rejected}

    machine.lock

    # Test shorthand syntax works
    assert machine.can_trigger?(:publish)
    result = machine.trigger(:publish)
    assert result.successful?
    assert_equal "created", result.from
    assert_equal "published", result.to
    assert_equal "published", machine.current_state

    # Test all syntax styles produce equivalent results
    machine_rules = machine.to_h[:rules]
    expected_publish_rules = [{"approved" => "published"}, {"created" => "published"}]
    expected_reject_rules = [{"submitted" => "rejected"}, {"approved" => "rejected"}]

    assert_equal expected_publish_rules.sort_by(&:to_s), machine_rules["publish"].sort_by(&:to_s)
    assert_equal expected_reject_rules.sort_by(&:to_s), machine_rules["reject"].sort_by(&:to_s)
    assert_equal expected_publish_rules.sort_by(&:to_s), machine_rules["publish_verbose"].sort_by(&:to_s)
    assert_equal expected_reject_rules.sort_by(&:to_s), machine_rules["reject_verbose"].sort_by(&:to_s)
  end

  def test_error_handling
    # Test Error Handling section examples from README

    # Matrix errors (StateJacket::Matrix::Error)
    matrix = StateJacket::Matrix.new
    matrix.lock

    error = assert_raises(StateJacket::Matrix::Error) do
      matrix.add created: :submitted  # Error: additions not permitted when locked
    end
    assert_equal "additions not permitted when locked", error.message

    # Machine errors (StateJacket::Machine::Error)
    matrix = StateJacket::Matrix.new
    matrix.add created: :submitted
    matrix.lock

    error = assert_raises(StateJacket::Machine::Error) do
      StateJacket::Machine.new(matrix, current_state: :invalid)
    end
    assert_match(/illegal state 'invalid'/, error.message)

    # Common error scenarios
    machine = StateJacket::Machine.new(matrix, current_state: :created)
    machine.lock

    error = assert_raises(StateJacket::Machine::Error) do
      machine.trigger(:undefined_event)
    end
    assert_match(/event 'undefined_event' not defined/, error.message)
  end

  def test_core_concepts_examples
    # Test all Core Concepts examples from README

    # Matrix examples
    matrix = StateJacket::Matrix.new

    # Single transitions
    matrix.add created: :submitted     # submitted for review
    matrix.add approved: :published

    # Multiple target states
    matrix.add submitted: [:approved, :rejected]

    # Terminal states (no outgoing transitions)
    matrix.add :published
    matrix.add :rejected

    matrix.lock # Prevent further modifications

    assert matrix.locked?
    assert_includes matrix.states, "created"
    assert_includes matrix.states, "submitted"
    assert_includes matrix.states, "published"
    assert_includes matrix.states, "approved"
    assert_includes matrix.states, "rejected"

    # Machine examples
    machine = StateJacket::Machine.new(matrix, current_state: :created)

    # Define events and their transitions
    machine.on :submit, matrix[:created_to_submitted]
    machine.on :approve, matrix[:submitted_to_approved]
    machine.on :reject, matrix[:submitted_to_rejected]
    machine.on :publish, matrix[:approved_to_published]

    machine.lock # Prevent further event definitions

    # Trigger events
    result = machine.trigger(:submit)
    assert result.successful?
    assert_equal "created", result.from
    assert_equal "submitted", result.to
    assert_equal "submitted", machine.current_state
  end

  def test_introspection_examples
    # Test Introspection section examples from README
    matrix = StateJacket::Matrix.new
    matrix.add created: :submitted
    matrix.add submitted: [:approved, :rejected]
    matrix.add approved: :published
    matrix.lock

    # Matrix introspection
    assert_includes matrix.states, "created"             # All states
    assert_includes matrix.transitioners, "created"      # States with outgoing transitions
    assert_includes matrix.terminals, "rejected"         # States with no outgoing transitions
    assert matrix.include?(:created)                     # Check if state exists

    machine = StateJacket::Machine.new(matrix, current_state: :created)
    machine.on :submit, matrix[:created_to_submitted]
    machine.on :approve, matrix[:submitted_to_approved]
    machine.on :reject, matrix[:submitted_to_rejected]
    machine.on :publish, matrix[:approved_to_published]
    machine.lock

    # Machine introspection
    assert_equal "created", machine.current_state         # Current state
    assert !machine.finished?                            # Is in terminal state?
    assert machine.can_trigger?(:submit)                 # Can event be triggered?
    assert_includes machine.triggerable_events, "submit" # All events that can be triggered now
    assert_includes machine.reachable_states, "submitted" # States reachable from current state
  end

  def test_matrix_validation_methods
    # Test Matrix Validation Methods from Advanced API Features section
    matrix = StateJacket::Matrix.new
    matrix.add created: [:submitted, :archived]
    matrix.add submitted: :approved
    matrix.lock

    # allows? - Checks if specific transition is allowed (loose validation)
    assert matrix.allows?(created: :submitted)   # => true
    assert !matrix.allows?(created: :invalid)    # => false
    assert !matrix.allows?(submitted: :archived) # => false

    # overlaps? - Checks if any specified transitions overlap with defined rules
    assert matrix.overlaps?(created: [:submitted, :published]) # => true (submitted overlaps)
    assert !matrix.overlaps?(created: [:invalid, :fake])       # => false (no overlap)

    # match? - Checks if rule strictly matches a defined transition rule (exact validation)
    assert matrix.match?(created: [:submitted, :archived]) # => true (exact match)
    assert !matrix.match?(created: :submitted)             # => false (partial match)
    assert matrix.match?(submitted: :approved)             # => true (exact match)
  end

  def test_matrix_factory_methods
    # Test Matrix Factory Methods from Advanced API Features section
    # Create from hash data
    hash_data = {
      locked: true,
      rules: {
        "created" => ["submitted"],
        "submitted" => ["approved", "rejected"],
        "approved" => ["published"],
        "rejected" => nil,
        "published" => nil
      }
    }

    matrix = StateJacket::Matrix.from_hash(hash_data)
    # Alternative syntax
    matrix2 = StateJacket::Matrix.from_h(hash_data)

    # Matrix is automatically locked if hash includes locked: true
    assert matrix.locked? # => true
    assert_equal ["created", "submitted", "approved", "rejected", "published"].sort, matrix.states.sort
    assert_equal matrix.to_h, matrix2.to_h
  end

  def test_advanced_matrix_introspection
    # Test Advanced Matrix Introspection from Advanced API Features section
    matrix = StateJacket::Matrix.new
    matrix.add created: :submitted
    matrix.add submitted: [:approved, :rejected]
    matrix.add approved: :published
    matrix.lock

    # Check specific states
    assert matrix.include?(:created)       # => true
    assert !matrix.include?("invalid")     # => false
    assert matrix.terminal?(:published)    # => true
    assert matrix.transitioner?(:created)  # => true

    # Access individual transitions
    assert_equal({"created" => "submitted"}, matrix[:created_to_submitted])
    expected_keys = [:created_to_submitted, :submitted_to_approved, :submitted_to_rejected, :approved_to_published]
    assert_equal expected_keys.sort, matrix.transition_keys.sort
    assert matrix.transitions.is_a?(Hash)

    # Performance: locked matrices return cached values
    assert_equal matrix.states, matrix.cached_states
    assert_equal matrix.terminals, matrix.cached_terminals
    assert_equal matrix.transitioners, matrix.cached_transitioners
  end

  def test_machine_factory_methods
    # Test Machine Factory Methods from Advanced API Features section
    matrix = StateJacket::Matrix.new
    matrix.add created: :submitted
    matrix.add submitted: :approved
    matrix.lock

    # Create machine from serialized data
    machine_data = {
      locked: true,
      current_state: "submitted",
      rules: {
        "submit" => [{"created" => "submitted"}],
        "approve" => [{"submitted" => "approved"}]
      }
    }

    machine = StateJacket::Machine.from_hash(matrix, machine_data)
    # Alternative syntax
    machine2 = StateJacket::Machine.from_h(matrix, machine_data)

    assert machine.locked?
    assert_equal "submitted", machine.current_state
    assert_equal machine.to_h, machine2.to_h
  end

  def test_multi_state_event_definitions
    # Test Multi-State Event Definitions from Advanced API Features section
    matrix = StateJacket::Matrix.new
    matrix.add rejected: :archived
    matrix.add published: :archived
    matrix.add submitted: :created
    matrix.add approved: :created
    matrix.add rejected: :created  # Add this transition for reset event
    matrix.lock

    machine = StateJacket::Machine.new(matrix, current_state: :rejected)

    # Single event from multiple states
    machine.on :archive, [:rejected, :published] => :archived

    # Hash syntax for multiple transitions
    machine.on :reset, {
      submitted: :created,
      approved: :created,
      rejected: :created
    }

    machine.lock

    # Test archive works from rejected state
    assert machine.can_trigger?(:archive)
    result = machine.trigger(:archive)
    assert result.successful?
    assert_equal "archived", machine.current_state
  end

  def test_advanced_machine_introspection
    # Test Advanced Machine Introspection from Advanced API Features section
    matrix = StateJacket::Matrix.new
    matrix.add created: :submitted
    matrix.add submitted: :approved
    matrix.lock

    machine = StateJacket::Machine.new(matrix, current_state: :created)
    machine.on :submit, created: :submitted
    machine.on :approve, submitted: :approved
    machine.lock

    assert machine.include?(:submit)      # => true (event exists)
    assert !machine.can_trigger?(:approve) # => false (not triggerable from current state)
    assert_equal ["submit", "approve"].sort, machine.events.sort
    assert_equal matrix.states, machine.states # => All states from underlying matrix
  end

  def test_transition_result_objects
    # Test Transition Result Objects from Advanced API Features section
    matrix = StateJacket::Matrix.new
    matrix.add created: :submitted
    matrix.lock

    machine = StateJacket::Machine.new(matrix, current_state: :created)
    machine.on :submit, created: :submitted
    machine.lock

    result = machine.trigger(:submit)

    # Transition attributes
    assert_equal "submit", result.event    # => "submit"
    assert_equal "created", result.from    # => "created"
    assert_equal "submitted", result.to    # => "submitted"
    assert_equal :ok, result.status        # => :ok
    assert_nil result.error                # => nil

    # Convenience method
    assert result.successful? # => true

    # Pattern matching support
    matched = false
    case result
    in event: "submit", status: :ok, to: to_state
      matched = true
      assert_equal "submitted", to_state
    in status: :error, error: error
      flunk "Should not match error pattern"
    end
    assert matched
  end

  def test_symbol_and_string_handling
    # Test Symbol and String Handling from Advanced API Features section
    matrix = StateJacket::Matrix.new

    # These are equivalent
    matrix.add created: :submitted
    matrix.add "approved" => "published"
    matrix.lock

    # All return strings
    assert matrix.states.all? { |s| s.is_a?(String) }
    assert_equal ["created", "submitted", "approved", "published"].sort, matrix.states.sort

    machine = StateJacket::Machine.new(matrix, current_state: :created)
    machine.on :submit, created: :submitted
    machine.lock

    assert machine.events.all? { |e| e.is_a?(String) }
    assert_equal ["submit"], machine.events
    assert_equal "created", machine.current_state

    # API accepts both
    assert matrix.include?(:created)   # => true
    assert matrix.include?("created")  # => true
  end

  def test_empty_matrix
    # Test Empty Matrix from Edge Cases section
    matrix = StateJacket::Matrix.new
    assert_equal [], matrix.states # => []
    matrix.lock # Valid - creates empty locked matrix
    assert matrix.locked?
  end

  def test_self_referential_states
    # Test Self-referential States from Edge Cases section
    matrix = StateJacket::Matrix.new
    matrix.add state_a: :state_a # Valid - state transitions to itself
    matrix.lock

    assert_includes matrix.states, "state_a"
    assert matrix.allows?(state_a: :state_a)
  end

  def test_circular_references
    # Test Circular References from Edge Cases section
    matrix = StateJacket::Matrix.new
    matrix.add state_a: :state_b
    matrix.add state_b: :state_c
    matrix.add state_c: :state_a # Valid - creates cycle
    matrix.lock

    assert_equal ["state_a", "state_b", "state_c"].sort, matrix.states.sort
    assert matrix.allows?(state_a: :state_b)
    assert matrix.allows?(state_b: :state_c)
    assert matrix.allows?(state_c: :state_a)
  end

  def test_terminal_state_handling
    # Test Terminal State Handling from Edge Cases section
    matrix = StateJacket::Matrix.new
    matrix.add pending: nil  # Explicit terminal
    matrix.add :finished     # Implicit terminal (no outgoing transitions)
    matrix.lock

    assert_includes matrix.terminals, "pending"
    assert_includes matrix.terminals, "finished"
    assert_equal ["pending", "finished"].sort, matrix.terminals.sort
  end

  def test_unicode_and_special_characters
    # Test Unicode and Special Characters from Edge Cases section
    matrix = StateJacket::Matrix.new

    # Unicode support
    matrix.add "创建" => "提交"           # Chinese characters
    matrix.add "제출" => "승인됨"         # Korean characters
    matrix.add created: :launched
    matrix.lock

    machine = StateJacket::Machine.new(matrix, current_state: "创建")

    # Korean event
    machine.on "승인", "제출" => "승인됨"

    # Special characters
    machine.on "event-with-dashes", created: :launched
    machine.on "event_with_underscores", created: :launched
    machine.on "event.with.dots", created: :launched
    machine.on "🚀", created: :launched # Emoji support

    machine.lock

    # Test Chinese transition works
    machine_cn = StateJacket::Machine.new(matrix, current_state: "创建")
    machine_cn.on "提交", "创建" => "提交"
    machine_cn.lock
    result = machine_cn.trigger("提交")
    assert result.successful?
    assert_equal "提交", machine_cn.current_state

    # Test special character events work
    assert_includes machine.events, "event-with-dashes"
    assert_includes machine.events, "event_with_underscores"
    assert_includes machine.events, "event.with.dots"
    assert_includes machine.events, "🚀"
  end

  def test_machine_pattern_matching
    # Test Machine Pattern Matching from Pattern Matching section
    matrix = StateJacket::Matrix.new
    matrix.add submitted: :approved
    matrix.add approved: :published
    matrix.add rejected: :archived
    matrix.add published: :archived
    matrix.lock

    machine = StateJacket::Machine.new(matrix, current_state: :submitted)
    machine.on :approve, submitted: :approved
    machine.on :publish, approved: :published
    machine.on :archive, [:rejected, :published] => :archived
    machine.lock

    # Match on machine state
    result = case machine
    in current_state: "submitted", finished: false
      "Handle machines in submitted state"
    in current_state: state, finished: true
      "Handle terminal states with state extraction: #{state}"
    in triggerable_events: [*, "approve", *]
      "Handle machines that can approve"
    end

    assert_equal "Handle machines in submitted state", result
  end

  def test_matrix_pattern_matching
    # Test Matrix Pattern Matching from Pattern Matching section
    matrix = StateJacket::Matrix.new
    matrix.add created: :submitted
    matrix.add submitted: :approved
    matrix.add approved: :published
    matrix.add :published
    matrix.lock

    # Match on matrix structure
    result = case matrix
    in locked: true, terminals: terminals if terminals.include?("published")
      "Handle matrices with published terminal"
    in states: states if states.length > 5
      "Handle complex matrices"
    end

    assert_equal "Handle matrices with published terminal", result
  end

  def test_advanced_transition_pattern_matching
    # Test Advanced Transition Pattern Matching from Pattern Matching section
    matrix = StateJacket::Matrix.new
    matrix.add draft: :published
    matrix.add submitted: :approved
    matrix.lock

    machine = StateJacket::Machine.new(matrix, current_state: :draft)
    machine.on :publish, draft: :published
    machine.on :approve, submitted: :approved
    machine.lock

    result = machine.trigger(:publish)

    # Complex error handling with pattern matching
    matched_pattern = case result
    in status: :ok, from: "draft", to: "published"
      "Direct draft-to-published transition"
    in status: :ok, to: "approved"
      "Any transition to approved state"
    in status: :error, error: StateJacket::Machine::Error => e
      "StateJacket system errors"
    in status: :error, error: ArgumentError => e
      "Business logic validation errors"
    in status: :error, error: StandardError => e
      "General application errors"
    else
      "Fallback for unexpected cases"
    end

    assert_equal "Direct draft-to-published transition", matched_pattern
  end

  def test_thread_safe_matrix_operations
    # Test Thread Safety examples from Thread Safety Guarantees section
    matrix = StateJacket::Matrix.new
    matrix.add created: :submitted
    matrix.add submitted: [:approved, :rejected]
    matrix.add approved: :published
    matrix.lock

    results = []
    mutex = Mutex.new

    # Matrix thread-safe read operations
    threads = 10.times.map do
      Thread.new do
        # Basic introspection (always safe)
        states = matrix.states
        matrix.transitioners
        matrix.terminals
        matrix.rules
        matrix.locked?

        # State validation (synchronized)
        include_created = matrix.include?(:created)
        terminal_published = matrix.terminal?(:published)
        matrix.transitioner?(:submitted)

        # Transition validation (synchronized)
        allows = matrix.allows?(created: :submitted)
        matrix.overlaps?(created: [:submitted, :published])
        matrix.match?(created: [:submitted])

        # Transition lookup (cached when locked)
        matrix[:created_to_submitted]
        matrix.transition_keys
        matrix.transitions

        # Cached data access (when locked, no synchronization needed)
        matrix.cached_states
        matrix.cached_terminals
        matrix.cached_transitioners

        # Serialization (uses other thread-safe methods)
        matrix.to_h
        matrix.deconstruct_keys([:states])

        mutex.synchronize do
          results << {
            states_count: states.length,
            include_created: include_created,
            terminal_published: terminal_published,
            allows: allows
          }
        end
      end
    end

    threads.each(&:join)

    # All threads should see the same data
    assert_equal 10, results.length
    assert results.all? { |r| r[:states_count] == 5 }
    assert results.all? { |r| r[:include_created] == true }
    assert results.all? { |r| r[:terminal_published] == true }
    assert results.all? { |r| r[:allows] == true }
  end

  def test_thread_safe_machine_operations
    # Test Machine thread-safe operations from Thread Safety Guarantees section
    matrix = StateJacket::Matrix.new
    matrix.add created: :submitted
    matrix.add submitted: :approved
    matrix.lock

    machine = StateJacket::Machine.new(matrix, current_state: :created)
    machine.on :submit, created: :submitted
    machine.on :approve, submitted: :approved
    machine.lock

    results = []
    mutex = Mutex.new

    # Machine thread-safe read operations
    threads = 10.times.map do
      Thread.new do
        # Basic introspection (atomic reads)
        current = machine.current_state
        machine.locked?
        machine.finished?

        # Event introspection (synchronized)
        events = machine.events
        machine.include?(:submit)
        can_trigger = machine.can_trigger?(:submit)
        machine.triggerable_events
        machine.reachable_states
        machine.rules

        # Matrix access (all matrix methods available)
        machine.states
        machine.matrix.terminals

        # Serialization (uses other thread-safe methods)
        machine.to_h
        machine.deconstruct_keys([:current_state])

        mutex.synchronize do
          results << {
            current_state: current,
            can_trigger_submit: can_trigger,
            events_count: events.length
          }
        end
      end
    end

    threads.each(&:join)

    # All threads should see the same initial state
    assert_equal 10, results.length
    assert results.all? { |r| r[:current_state] == "created" }
    assert results.all? { |r| r[:can_trigger_submit] == true }
    assert results.all? { |r| r[:events_count] == 2 }
  end

  def test_concurrent_transitions
    # Test safe concurrent transitions from Thread Safety Guarantees section
    matrix = StateJacket::Matrix.new
    matrix.add created: :submitted
    matrix.lock

    machine = StateJacket::Machine.new(matrix, current_state: :created)
    machine.on :submit, created: :submitted
    machine.lock

    success_count = 0
    mutex = Mutex.new

    # Safe concurrent transitions
    threads = 10.times.map do
      Thread.new do
        # Only one thread will succeed in transitioning
        if machine.can_trigger?(:submit)
          result = machine.trigger(:submit)
          mutex.synchronize { success_count += 1 } if result.successful?
        end
      end
    end

    threads.each(&:join)

    # Only one thread should have succeeded
    assert_equal 1, success_count
    assert_equal "submitted", machine.current_state
  end

  def test_thread_safe_factory_methods
    # Test thread-safe factory methods from Thread Safety Guarantees section
    saved_matrix_data = {
      locked: true,
      rules: {
        "created" => ["submitted"],
        "submitted" => ["approved"]
      }
    }

    saved_machine_data = {
      locked: true,
      current_state: "created",
      rules: {
        "submit" => [{"created" => "submitted"}],
        "approve" => [{"submitted" => "approved"}]
      }
    }

    created_objects = []
    mutex = Mutex.new

    # Factory methods are thread-safe (create new instances)
    threads = 10.times.map do
      Thread.new do
        # Safe to create from serialized data concurrently
        new_matrix = StateJacket::Matrix.from_hash(saved_matrix_data)
        new_machine = StateJacket::Machine.from_hash(new_matrix, saved_machine_data)

        mutex.synchronize do
          created_objects << {matrix: new_matrix, machine: new_machine}
        end
      end
    end

    threads.each(&:join)

    # All threads should have created independent objects
    assert_equal 10, created_objects.length
    # Each object should be unique
    matrices = created_objects.map { |o| o[:matrix] }
    machines = created_objects.map { |o| o[:machine] }
    assert_equal 10, matrices.uniq.length
    assert_equal 10, machines.uniq.length
  end

  def test_transition_thread_safety
    # Test Transition objects thread safety from Thread Safety Guarantees section
    matrix = StateJacket::Matrix.new
    matrix.add created: :submitted
    matrix.lock

    machine = StateJacket::Machine.new(matrix, current_state: :created)
    machine.on :submit, created: :submitted
    machine.lock

    result = machine.trigger(:submit)
    accessed_values = []
    mutex = Mutex.new

    # Transition objects are completely thread-safe (immutable structs)
    threads = 10.times.map do
      Thread.new do
        # All Transition methods are thread-safe
        event = result.event
        from = result.from
        to = result.to
        result.status
        result.error
        successful = result.successful?
        result.to_h
        result.deconstruct_keys([:status])

        mutex.synchronize do
          accessed_values << {
            event: event,
            from: from,
            to: to,
            successful: successful
          }
        end
      end
    end

    threads.each(&:join)

    # All threads should see the same values
    assert_equal 10, accessed_values.length
    assert accessed_values.all? { |v| v[:event] == "submit" }
    assert accessed_values.all? { |v| v[:from] == "created" }
    assert accessed_values.all? { |v| v[:to] == "submitted" }
    assert accessed_values.all? { |v| v[:successful] == true }
  end
end
