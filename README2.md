# StateJacket

A simple, powerful state machine library for Ruby.

<!-- toc -->

- [Getting Started](#getting-started)
- [Key Features](#key-features)
  - [Transition Helpers](#transition-helpers)
  - [Data Immutability](#data-immutability)
  - [Naming Conventions](#naming-conventions)
- [Core Concepts](#core-concepts)
  - [Matrix](#matrix)
  - [Machine](#machine)
  - [Workflow](#workflow)
- [Thread Safety](#thread-safety)
- [Error Handling](#error-handling)
- [Introspection](#introspection)
- [Advanced Usage](#advanced-usage)
  - [Workflow Persistence](#workflow-persistence)
  - [Advanced API Features](#advanced-api-features)
- [Edge Cases](#edge-cases)
  - [Special Workflow Patterns](#special-workflow-patterns)
  - [Unicode and Special Characters](#unicode-and-special-characters)
- [Pattern Matching](#pattern-matching)
  - [Machine Pattern Matching](#machine-pattern-matching)
  - [Matrix Pattern Matching](#matrix-pattern-matching)
  - [Advanced Transition Pattern Matching](#advanced-transition-pattern-matching)
- [Thread Safety Guarantees](#thread-safety-guarantees)
  - [Synchronization Guarantees](#synchronization-guarantees)
  - [Concurrent Usage Patterns](#concurrent-usage-patterns)
  - [Deadlock Prevention](#deadlock-prevention)
- [Benchmarks](#benchmarks)
  - [Performance Highlights](#performance-highlights)
  - [Performance Characteristics](#performance-characteristics-1)
  - [Running Benchmarks](#running-benchmarks)

<!-- tocstop -->

## Getting Started

Let's build a simple content publishing workflow with StateJacket. Our workflow has five states representing the lifecycle of a document:

> [!NOTE]
> This is an intentionally simple example to help you quickly grasp StateJacket's core concepts. We'll explore more complex workflows and advanced features in the sections that follow.

**States:**

- `created` → Initial state when content is first created
- `submitted` → Content has been submitted for review
- `approved` → Content has been reviewed and approved for publication
- `rejected` → Content was reviewed but rejected (needs changes)
- `published` → Content is live and publicly available

**Events (actions that trigger transitions):**

- `submit` → Author submits content for review
- `approve` → Reviewer approves the content
- `reject` → Reviewer rejects the content (requests changes)
- `publish` → Editor publishes the approved content

**Workflow:**

```
created → submit → submitted → approve → approved → publish → published
                        ↓
                     reject
                        ↓
                    rejected
```

Now let's implement this with StateJacket:

```ruby
# Define the state transition rules
matrix = StateJacket::Matrix.new
matrix.add :created => :submitted
matrix.add :submitted => [:approved, :rejected]
matrix.add :approved => :published

# Access transitions before locking (convenient for machine setup)
matrix[:created_to_submitted] # => {"created" => "submitted"}
matrix.transition_keys        # => [:created_to_submitted, :submitted_to_approved, ...]

matrix.lock
matrix.to_h
{
  locked: true,
  states: [ "created", "submitted", "approved", "rejected", "published" ],
  transitioners: [ "created", "submitted", "approved" ],
  terminals: [ "rejected", "published" ],
  rules: {
    "created" => [ "submitted" ],
    "submitted" => [ "approved", "rejected" ],
    "approved" => [ "published" ],
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

# Create a state machine using the matrix
machine = StateJacket::Machine.new(matrix, :current_state => :created)

# Use transition helpers for cleaner event definitions
machine.on :submit, matrix[:created_to_submitted]
machine.on :approve, matrix[:submitted_to_approved]
machine.on :reject, matrix[:submitted_to_rejected]
machine.on :publish, matrix[:approved_to_published]

machine.lock
machine.to_h
{
  locked: true,
  current_state: "created",
  finished: false,
  reachable_states: [ "submitted" ],
  triggerable_events: [ "submit" ],
  rules: {
    "submit" => [ {"created" => "submitted"} ],
    "approve" => [ {"submitted" => "approved"} ],
    "reject" => [ {"submitted" => "rejected"} ],
    "publish" => [ {"approved" => "published"} ]
  }
}
```

## Key Features

### Transition Helpers

Matrix provides convenient helpers to access individual transitions:

```ruby
# Access transitions by key
matrix[:created_to_submitted] # => {"created" => "submitted"}

# List all available transitions
matrix.transition_keys # => [:created_to_submitted, :submitted_to_approved, ...]

# Works even before locking (returns frozen copies)
matrix = StateJacket::Matrix.new
matrix.add :created => :published
transition = matrix[:created_to_published] # => {"created" => "published"}
transition.frozen?                         # => true

# Alternative syntax (shorthand)
# machine.on :publish, [:approved, :created] => :published
# machine.on :reject, [:submitted, :approved] => :rejected

# Alternative syntax (verbose)
# machine.on :publish, {:approved => :published, :created => :published}
# machine.on :reject, {:submitted => :rejected, :approved => :rejected}
```

### Data Immutability

All data returned by introspection methods is frozen to prevent accidental modification:

```ruby
states = matrix.states
states.frozen?       # => true
states << "archived" # => FrozenError

rules = matrix.rules
rules["created"] = ["archived"] # => FrozenError
rules["created"] << "archived"  # => FrozenError
```

### Naming Conventions

> [!NOTE]
>
> **Recommended Conventions**: Use past tense for matrix states (`:created`, `:submitted`), and present tense for machine events (`:create`, `:submit`). Use different names for machine events than matrix states. _While not strictly required, these conventions help avoid confusion and make state machines more intuitive._

- **Matrix States**: Past tense (represents a completed transition)
  - Examples: `:created`, `:submitted`, `:approved`, `:rejected`, `:published`
- **Machine Events**: Present tense (represents an action to take)
  - Can be present tense versions of state names: `:create`, `:submit`, `:approve`, `:reject`, `:publish`
  - Or completely different names that describe the action: `:init`, `:review`, `:accept`, `:decline`

**Why these conventions matter:**

Matrix states represent the outcome of completed actions, so past tense naturally communicates "this has already happened" (`:published`, `:submitted`). Machine events represent actions you want to trigger, so present tense communicates "do this now" (`:publish`, `:submit`).

Using different names for events and states prevents confusion in your code - when you see `:submit` it's clearly an action to take, while `:submitted` is clearly a state something is in. This distinction becomes especially valuable in larger applications where the intent behind each identifier needs to be immediately clear.

## Core Concepts

### Matrix

Defines the allowed state transitions as a directed graph:

```ruby
matrix = StateJacket::Matrix.new

# Single transitions
matrix.add :created => :submitted # submitted for review
matrix.add :approved => :published

# Multiple target states
matrix.add :submitted => [:approved, :rejected]

# Terminal states (no outgoing transitions)
matrix.add :published
matrix.add :rejected

matrix.lock # Prevent further modifications
```

### Machine

Executes state transitions based on events:

```ruby
machine = StateJacket::Machine.new(matrix, current_state: :created)

# Define events and their transitions
machine.on :submit, matrix[:created_to_submitted]
machine.on :approve, matrix[:submitted_to_approved]
machine.on :reject, matrix[:submitted_to_rejected]
machine.on :publish, matrix[:approved_to_published]

machine.lock # Prevent further event definitions

# Trigger events
result = machine.trigger(:submit)
result.successful?    # => true
result.from           # => "created"
result.to             # => "submitted"
machine.current_state # => "submitted"
```

### Workflow

Now let's see how to integrate business logic and error handling when triggering machine events:

```ruby
# Continue with our existing machine (currently in "submitted" state)
# Trigger approval with business logic
result = machine.trigger(:approve) do |from, to|
  # Business logic (guards, etc.)
  raise "Reviewer not authorized" unless current_user.can_approve?

  # Business logic (side effects)
  puts "Approving content (#{from} → #{to})"
  update_database_timestamp(:approved_at, Time.now)
  update_content_status(content_id, :approved)
  create_audit_log("Content approved", reviewer: current_user.id)
end

# After executing a trigger, check the result and react accordingly
if result.successful?
  # Business logic that reacts to successful transition
  puts "Success: #{result.from} → #{result.to}"
  puts "Current state: #{machine.current_state}" # => "approved"
  send_notification_to_author("Your content has been approved!")
  redirect_to_approval_dashboard
  flash_success_message("Content approved!")
else
  # Business logic that reacts to failed transition (state unchanged)
  puts "Transition failed: #{result.error.message}"
  puts "State unchanged: #{machine.current_state}" # => "submitted"
  log_approval_failure(result.error)
  redirect_back_with_error(result.error.message)
end
```

For more sophisticated workflows, pattern matching lets you elegantly handle specific states and errors with cleaner, more expressive code:

```ruby
case result
in status: :ok, to: "approved"
  # Business logic that reacts to successful transition
  puts "Successfully approved - ready for publication"
  send_notification_to_author("Your content has been approved!")
  redirect_to_approval_dashboard
  flash_success_message("Content approved!")
in status: :error, error: StateJacket::Machine::Error => e
  # StateJacket-specific errors (invalid transitions, etc. - state unchanged)
  puts "StateJacket error: #{e.message}"
  log_system_error(e)
  redirect_back_with_error("System error occurred")
in status: :error, error: StandardError => e
  # Business logic errors (authorization, validation, etc. - state unchanged)
  puts "Business logic error: #{e.message}"
  log_approval_failure(e)
  redirect_back_with_error(e.message)
end
```

Key workflow concepts:

- **Business Logic Integration**: Execute code during transitions using blocks
- **Built-in Error Handling**: StateJacket captures exceptions and returns them in the result object
- **State Preservation**: State only changes if the block executes successfully without exceptions
- **Result Checking**: Always check `result.successful?` and `result.error` rather than using begin/rescue

> [!IMPORTANT]
>
> **Business Logic Placement Strategy**
>
> **Inside the trigger block:** Put logic that's part of the state transition itself - validation, authorization checks, database updates that are atomic with the state change, and audit logging. If any of this fails, the transition should not occur.
>
> **In result handlers:** Put logic that reacts to the transition outcome - UI updates, redirects, notifications, error reporting, and cleanup actions. This logic should run based on whether the transition succeeded or failed, and shouldn't affect the state change itself.
>
> **Why this separation matters:** It creates clear separation between transition logic (what must happen for the state to change) and reaction logic (what happens because the state changed). This makes code more testable, maintainable, and allows different contexts to react differently to the same state transitions.

## Thread Safety

StateJacket is thread-safe by design. All operations are synchronized to prevent race conditions:

```ruby
# Safe to use across multiple threads
threads = 10.times.map do
  Thread.new do
    machine.trigger(:approve) if machine.can_trigger?(:approve)
  end
end
threads.each(&:join)
```

## Error Handling

StateJacket defines custom error classes for clear error identification:

```ruby
# Matrix errors (StateJacket::Matrix::Error)
begin
  matrix = StateJacket::Matrix.new
  matrix.lock
  matrix.add created: :submitted # Error: additions not permitted when locked
rescue StateJacket::Matrix::Error => error
  puts error.message # => "additions not permitted when locked"
end

# Machine errors (StateJacket::Machine::Error)
begin
  matrix = StateJacket::Matrix.new
  matrix.add created: :submitted
  matrix.lock

  machine = StateJacket::Machine.new(matrix, current_state: :invalid)
rescue StateJacket::Machine::Error => error
  puts error.message # => "illegal state 'invalid'. Available states: [...]"
end

# Common error scenarios
begin
  machine.trigger(:undefined_event)
rescue StateJacket::Machine::Error => error
  puts error.message # => "event 'undefined_event' not defined. Available events: [...]"
end
```

## Introspection

Both Matrix and Machine provide rich introspection capabilities:

```ruby
# Matrix introspection
matrix.states             # All states
matrix.transitioners      # States with outgoing transitions
matrix.terminals          # States with no outgoing transitions
matrix.include?(:created) # Check if state exists

# Machine introspection
machine.current_state         # Current state
machine.finished?             # Is in terminal state?
machine.can_trigger?(:submit) # Can event be triggered?
machine.triggerable_events    # All events that can be triggered now
machine.reachable_states      # States reachable from current state
```

## Advanced Usage

### Workflow Persistence

Save and restore state machines for long-running workflows:

```ruby
# Save state
data = {
  matrix: matrix.to_h,
  machine: machine.to_h
}
File.write("workflow.json", JSON.dump(data))

# Restore later
data = JSON.parse(File.read("workflow.json"), symbolize_names: true)
matrix = StateJacket::Matrix.from_hash(data[:matrix])
machine = StateJacket::Machine.from_hash(matrix, data[:machine])
```

#### Evolving Workflows Over Time

StateJacket supports workflow evolution by allowing you to modify the matrix definition while preserving existing workflow state. This is perfect for long-running processes where business requirements change:

```ruby
# Original workflow
original_matrix = StateJacket::Matrix.new
original_matrix.add :created => :submitted
original_matrix.add :submitted => [:approved, :rejected]
original_matrix.add :approved => :published
original_matrix.lock

machine = StateJacket::Machine.new(original_matrix, :current_state => :published)
machine.on :submit, original_matrix[:created_to_submitted]
machine.on :approve, original_matrix[:submitted_to_approved]
machine.on :reject, original_matrix[:submitted_to_rejected]
machine.on :publish, original_matrix[:approved_to_published]
machine.lock

# Save current state to file
workflow_data = { matrix: original_matrix.to_h, machine: machine.to_h }
File.write("workflow.json", JSON.dump(workflow_data))

# Later: Business requires archiving capability
# Load saved workflow data
saved_data = JSON.parse(File.read("workflow.json"), symbolize_names: true)
# Start from the original matrix definition (excluding locked state)
evolved_matrix = StateJacket::Matrix.from_hash(saved_data[:matrix].except(:locked))

# Add new archiving transitions using shorthand syntax
evolved_matrix.add [:created, :rejected, :published] => :archived
evolved_matrix.lock

# Inspect the evolved matrix
evolved_matrix.to_h
# => {
#      locked: true,
#      states: ["created", "submitted", "approved", "rejected", "published", "archived"],
#      transitioners: ["created", "submitted", "approved", "rejected", "published"],
#      terminals: ["archived"],
#      rules: {
#        "created" => ["submitted", "archived"],
#        "submitted" => ["approved", "rejected"],
#        "approved" => ["published"],
#        "rejected" => ["archived"],
#        "published" => ["archived"],
#        "archived" => nil
#      },
#      transitions: {
#        created_to_submitted: {"created" => "submitted"},
#        submitted_to_approved: {"submitted" => "approved"},
#        submitted_to_rejected: {"submitted" => "rejected"},
#        approved_to_published: {"approved" => "published"},
#        created_to_archived: {"created" => "archived"},
#        rejected_to_archived: {"rejected" => "archived"},
#        published_to_archived: {"published" => "archived"}
#      }
#    }

# Resume workflow with evolved system using saved machine definition
resumed_machine = StateJacket::Machine.from_hash(evolved_matrix, saved_data[:machine].except(:locked))

# Add new archive event using shorthand syntax
resumed_machine.on :archive, [:created, :rejected, :published] => :archived
resumed_machine.lock

# Inspect the evolved workflow to see what changed
resumed_machine.to_h
# => {
#      locked: true,
#      current_state: "published",
#      finished: false,
#      reachable_states: ["archived"],
#      triggerable_events: ["archive"],
#      rules: {
#        "submit" => [{"created" => "submitted"}],
#        "approve" => [{"submitted" => "approved"}],
#        "reject" => [{"submitted" => "rejected"}],
#        "publish" => [{"approved" => "published"}],
#        "archive" => [{"created" => "archived"}, {"rejected" => "archived"}, {"published" => "archived"}]
#      }
#    }

# Now the workflow supports archiving from its current :published state
resumed_machine.can_trigger?(:archive)  # => true
result = resumed_machine.trigger(:archive) do |from, to|
  puts "Archiving content: transitioning from #{from} to #{to}"
  # Send notifications, update database, audit log, etc.
end
result.successful?            # => true
resumed_machine.current_state # => "archived"
```

### Advanced API Features

#### Matrix Validation Methods

StateJacket provides three different validation methods for checking transitions:

```ruby
matrix = StateJacket::Matrix.new
matrix.add :created => [:submitted, :archived]
matrix.add :submitted => :approved
matrix.lock

# allows? - Checks if specific transition is allowed (loose validation)
matrix.allows?(:created => :submitted)  # => true
matrix.allows?(:created => :invalid)    # => false
matrix.allows?(:submitted => :archived) # => false

# overlaps? - Checks if any specified transitions overlap with defined rules
matrix.overlaps?(:created => [:submitted, :published]) # => true (submitted overlaps)
matrix.overlaps?(:created => [:invalid, :fake])        # => false (no overlap)

# match? - Checks if rule strictly matches a defined transition rule (exact validation)
matrix.match?(:created => [:submitted, :archived]) # => true (exact match)
matrix.match?(:created => :submitted)              # => false (partial match)
matrix.match?(:submitted => :approved)             # => true (exact match)
```

**When to use each method:**

- `allows?` - Validate individual transitions before triggering
- `overlaps?` - Check for partial compatibility with existing rules
- `match?` - Verify exact rule definitions for workflow validation

#### Matrix Factory Methods

Create matrices from serialized data for workflow restoration:

```ruby
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
matrix = StateJacket::Matrix.from_h(hash_data)

# Matrix is automatically locked if hash includes locked: true
matrix.locked? # => true
matrix.states  # => ["created", "submitted", "approved", "rejected", "published"]
```

#### Advanced Matrix Introspection

Query specific states and access transition details:

```ruby
matrix = StateJacket::Matrix.new
matrix.add :created => :submitted
matrix.add :submitted => [:approved, :rejected]
matrix.add :approved => :published
matrix.lock

# Check specific states
matrix.include?(:created)      # => true
matrix.include?("invalid")     # => false
matrix.terminal?(:published)   # => true
matrix.transitioner?(:created) # => true

# Access individual transitions
matrix[:created_to_submitted] # => {"created" => "submitted"}
matrix.transition_keys        # => [:created_to_submitted, :submitted_to_approved, ...]
matrix.transitions            # => {created_to_submitted: {"created" => "submitted"}, ...}

# Performance: locked matrices return cached values
matrix.cached_states        # => ["created", "submitted", "approved", "rejected", "published"]
matrix.cached_terminals     # => ["rejected", "published"]
matrix.cached_transitioners # => ["created", "submitted", "approved"]
```

#### Advanced Machine Features

##### Machine Factory Methods

```ruby
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
machine = StateJacket::Machine.from_h(matrix, machine_data)
```

##### Multi-State Event Definitions

Define events that work from multiple source states:

```ruby
# Single event from multiple states
machine.on :archive, [:rejected, :published] => :archived

# Equivalent to defining separate transitions
machine.on :archive, :rejected => :archived
machine.on :archive, :published => :archived

# Hash syntax for multiple transitions
machine.on :reset, {
  :submitted => :created,
  :approved => :created,
  :rejected => :created
}
```

##### Advanced Machine Introspection

```ruby
machine.include?(:submit)     # => true (event exists)
machine.can_trigger?(:submit) # => false (not triggerable from current state)
machine.events                # => ["submit", "approve", "reject", "publish"]
machine.states                # => All states from underlying matrix
```

#### Transition Result Objects

The `Transition` class provides comprehensive information about transition outcomes:

```ruby
result = machine.trigger(:submit)

# Transition attributes
result.event  # => "submit"
result.from   # => "created"
result.to     # => "submitted"
result.status # => :ok or :error
result.error  # => nil (or exception object if error occurred)

# Convenience method
result.successful? # => true (same as result.status == :ok)

# Pattern matching support
case result
in event: "submit", status: :ok, to: to_state
  puts "Successfully transitioned to #{to_state}"
in status: :error, error: error
  puts "Transition failed: #{error.message}"
end
```

#### Performance and Caching

StateJacket optimizes performance through intelligent caching:

##### Matrix Caching

- **Unlocked matrices**: Compute values on-demand with synchronization
- **Locked matrices**: Cache frequently accessed data for optimal performance
- **Cache types**: States, terminals, transitioners, and transition helpers

##### Performance Characteristics

```ruby
# Before locking - computed each time
matrix.states    # O(n) with synchronization
matrix.terminals # O(n) with synchronization

# After locking - cached values
matrix.lock
matrix.states    # O(1) from cache
matrix.terminals # O(1) from cache
```

#### Symbol and String Handling

StateJacket normalizes all identifiers to strings internally while accepting both symbols and strings in the API:

```ruby
# These are equivalent
matrix.add :created => :submitted
matrix.add "created" => "submitted"

# All return strings
matrix.states         # => ["created", "submitted"] (always strings)
machine.events        # => ["submit"] (always strings)
machine.current_state # => "created" (always string)

# API accepts both
matrix.include?(:created)  # => true
matrix.include?("created") # => true
```

## Edge Cases

### Special Workflow Patterns

```ruby
# Empty matrix
matrix = StateJacket::Matrix.new
matrix.states # => []
matrix.lock   # Valid - creates empty locked matrix

# Self-referential states
matrix.add :state_a => :state_a # Valid - state transitions to itself

# Circular references
matrix.add :state_a => :state_b
matrix.add :state_b => :state_c
matrix.add :state_c => :state_a # Valid - creates cycle

# Terminal state handling
matrix.add :pending => nil # Explicit terminal
matrix.add :finished    # Implicit terminal (no outgoing transitions)
```

### Unicode and Special Characters

StateJacket supports Unicode and special characters in state and event names:

```ruby
# Unicode support
matrix.add "创建" => "提交"           # Chinese characters
machine.on "승인", "제출" => "승인됨" # Korean characters

# Special characters
machine.on "event-with-dashes", :created => :submitted
machine.on "event_with_underscores", :created => :submitted
machine.on "event.with.dots", :created => :submitted
machine.on "🚀", :created => :launched # Emoji support
```

## Pattern Matching

StateJacket provides comprehensive pattern matching support for modern Ruby workflows:

### Machine Pattern Matching

```ruby
# Match on machine state
case machine
in current_state: "submitted", finished: false
  # Handle machines in submitted state
in current_state: state, finished: true
  # Handle terminal states with state extraction
in triggerable_events: [*, "approve", *]
  # Handle machines that can approve
end
```

### Matrix Pattern Matching

```ruby
# Match on matrix structure
case matrix
in locked: true, terminals: terminals if terminals.include?("published")
  # Handle matrices with published terminal
in states: states if states.length > 5
  # Handle complex matrices
end
```

### Advanced Transition Pattern Matching

```ruby
# Complex error handling with pattern matching
case result
in status: :ok, from: "draft", to: "published"
  # Direct draft-to-published transition
in status: :ok, to: "approved"
  # Any transition to approved state
in status: :error, error: StateJacket::Machine::Error => e
  # StateJacket system errors
in status: :error, error: ArgumentError => e
  # Business logic validation errors
in status: :error, error: StandardError => e
  # General application errors
else
  # Fallback for unexpected cases
end
```

## Thread Safety Guarantees

StateJacket is designed for concurrent environments with comprehensive thread safety:

### Synchronization Guarantees

- **All modifications** are synchronized using `MonitorMixin`
- **Read operations** on locked objects are thread-safe without synchronization
- **Atomic state changes** ensure consistent state transitions
- **Cache access** is thread-safe for locked matrices and machines

### Concurrent Usage Patterns

StateJacket provides extensive thread-safe API coverage for concurrent applications:

```ruby
# Matrix thread-safe read operations
threads = 10.times.map do
  Thread.new do
    # Basic introspection (always safe)
    matrix.states        # All states
    matrix.transitioners # States with outgoing transitions
    matrix.terminals     # Terminal states
    matrix.rules         # Transition rules (deep frozen copy)
    matrix.locked?       # Lock status (atomic read)

    # State validation (synchronized)
    matrix.include? :created        # State existence check
    matrix.terminal? :published     # Terminal state check
    matrix.transitioner? :submitted # Transitioner check

    # Transition validation (synchronized)
    matrix.allows? created => :submitted     # Individual transition check
    matrix.overlaps? created => [:sub, :pub] # Overlap validation
    matrix.match? created => [:submitted]    # Exact match validation

    # Transition lookup (cached when locked)
    matrix[:created_to_submitted] # Individual transition
    matrix.transition_keys        # All transition keys
    matrix.transitions            # All transitions hash

    # Cached data access (when locked, no synchronization needed)
    matrix.cached_states        # Direct cached access
    matrix.cached_terminals     # Direct cached access
    matrix.cached_transitioners # Direct cached access
    matrix.cached_transitions   # Direct cached access

    # Serialization (uses other thread-safe methods)
    matrix.to_h                       # Hash representation
    matrix.deconstruct_keys [:states] # Pattern matching support
  end
end

# Machine thread-safe read operations
threads = 10.times.map do
  Thread.new do
    # Basic introspection (atomic reads)
    machine.current_state # Current state (atomic)
    machine.locked?       # Lock status (atomic)
    machine.finished?     # Terminal state check (delegates to matrix)

    # Event introspection (synchronized)
    machine.events               # All defined events
    machine.include? :submit     # Event existence check
    machine.can_trigger? :submit # Transition possibility check
    machine.triggerable_events   # Events available from current state
    machine.reachable_states     # States reachable from current state
    machine.rules                # Event-to-transition mapping

    # Matrix access (all matrix methods available)
    machine.states           # All states from underlying matrix
    machine.matrix.terminals # Access to matrix methods

    # Serialization (uses other thread-safe methods)
    machine.to_h                              # Hash representation
    machine.deconstruct_keys [:current_state] # Pattern matching support
  end
end

# Safe concurrent transitions
threads = 10.times.map do
  Thread.new do
    # Only one thread will succeed in transitioning
    machine.trigger(:submit) if machine.can_trigger?(:submit)
  end
end

# Factory methods are thread-safe (create new instances)
threads = 10.times.map do
  Thread.new do
    # Safe to create from serialized data concurrently
    new_matrix = StateJacket::Matrix.from_hash(saved_matrix_data)
    new_machine = StateJacket::Machine.from_hash(new_matrix, saved_machine_data)
  end
end

# Transition objects are completely thread-safe (immutable structs)
threads = 10.times.map do
  Thread.new do
    # All Transition methods are thread-safe
    result.event                      # Event name
    result.from                       # Source state
    result.to                         # Target state
    result.status                     # Transition status
    result.error                      # Error object (if any)
    result.successful?                # Success predicate
    result.to_h                       # Hash representation
    result.deconstruct_keys [:status] # Pattern matching
  end
end
```

### Deadlock Prevention

- **Reentrant locks** prevent deadlocks from nested method calls
- **Atomic operations** minimize lock duration
- **No circular dependencies** between synchronized methods

## Benchmarks

StateJacket delivers exceptional performance for state machine operations. The following benchmarks were collected on a modern system using the publisher workflow example:

> [!NOTE]
> StateJacket is designed to get out of your way. The library's overhead is minimal - most performance implications in real applications will come from your business logic _(database operations, API calls, validations)_ rather than StateJacket itself. These benchmarks demonstrate that StateJacket won't be the bottleneck in your workflow.

### Performance Highlights

**Core Workflow Operations:**

- **79,500+ complete workflows per second** - Full created→submitted→approved→published cycles
- **95,000+ workflows with minimal business logic per second** - Including counters and simple validation
- **365+ workflows with realistic business logic per second** - Simulating real-world latency from database operations, authorization checks, audit logging, etc.

**Matrix Operations (Locked/Cached):**

- **15M+ state lookups per second** - Accessing `matrix.states` and related operations
- **6.6M+ transition lookups per second** - Individual transition access via `matrix[:key]`
- **4.5M+ inclusion checks per second** - Validating state existence with `matrix.include?`

**Machine Introspection:**

- **28M+ current state reads per second** - Accessing `machine.current_state`
- **2.2M+ event validation checks per second** - Testing `machine.can_trigger?`
- **545K+ triggerable events lookups per second** - Getting available events from current state
- **383K+ reachable states calculations per second** - Finding states accessible from current position

**Serialization (Persistence):**

- **750K+ matrix serializations per second** - Converting matrices to hash format
- **186K+ machine serializations per second** - Converting machines to hash format
- **53K+ matrix deserializations per second** - Creating matrices from hash data
- **38K+ machine deserializations per second** - Creating machines from hash data

### Performance Characteristics

**Optimized Operations:**

- Locked matrices use intelligent caching for frequently accessed data
- State lookups on locked matrices are O(1) with no synchronization overhead
- Current state reads are atomic operations with minimal overhead

**Thread-Safe Operations:**

- All operations are fully synchronized using Ruby's `MonitorMixin`
- Read operations on locked objects achieve maximum performance
- Concurrent access patterns are optimized for multi-threaded applications

**Scalability:**

- Performance remains consistent across operation counts (1K to 1M operations)
- Memory usage is optimized through object reuse and caching strategies
- Complex workflows (7+ states, 10+ transitions) maintain high throughput

### Running Benchmarks

To run the benchmarks on your system:

```bash
bin/benchmark
```

The benchmark suite tests the publisher workflow along with comprehensive matrix operations, machine introspection, business logic integration, and serialization performance. Results will vary based on your hardware and Ruby version.
