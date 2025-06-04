# StateJacket

**A modern Ruby state machine library designed for complex workflows and long-running processes.**

StateJacket provides an intuitive, thread-safe approach to building state machines that can pause, resume, and evolve across process boundaries. Built for Ruby 3.x with first-class pattern matching support.

## Why StateJacket?

### The Problem

Most state machine libraries tightly couple transition rules with event handling, making them difficult to test, evolve, and reason about. They struggle with:

- Long-running workflows that span hours, days, or weeks
- Processes that need to pause and resume across system restarts
- Workflows that must evolve while preserving existing state
- Complex business logic that benefits from pattern matching
- Clear separation between what transitions are allowed vs. how they're triggered

### The Solution

StateJacket separates concerns through a two-layer architecture:

1. **TransitionSystem** (the railway network) - Defines what state transitions are possible
2. **StateMachine** (the train) - Handles events and executes transitions within those rules

This separation enables powerful capabilities like workflow resumption, system evolution, and cleaner testing.

## Quick Start

```ruby
gem install state_jacket
```

```ruby
require 'state_jacket'

# Define your transition rules
system = StateJacket::TransitionSystem.new
system.add :pending => [:approved, :rejected]
system.add :approved => :published
system.lock

# Create a state machine
machine = StateJacket::StateMachine.new(system, current_state: :pending)
machine.on :approve, :pending => :approved
machine.on :reject, :pending => :rejected
machine.on :publish, :approved => :published
machine.lock

# Execute transitions
result = machine.trigger(:approve)
puts result.successful? # => true
puts machine.current_state # => "approved"

# Use pattern matching (Ruby 3.x)
case machine
in current_state: "approved", triggerable_events: events
  puts "Can trigger: #{events}" # => ["publish"]
end
```

## Core Architecture

### Layer 1: TransitionSystem (The Railway Network)

The TransitionSystem defines a directed graph of states and their allowed transitions. Think of it as railway tracks - they define where trains can go, but don't control the trains themselves.

```ruby
system = StateJacket::TransitionSystem.new

# Add states and transitions
system.add :draft => :review                    # Single transition
system.add :review => [:approved, :rejected]    # Multiple targets
system.add [:approved, :rejected] => :archived  # Multiple sources
system.add :published => nil                    # Terminal state

system.lock # Lock to prevent further changes
```

> [!NOTE]
>
> **Why Hash Rocket?**
> The examples use hash rockets (`=>`) to visually indicate the directional flow of transitions, making state flows easier to read and understand at a glance.
>
> _You may find this technique helpful in your own code._

**Key Methods:**

- `allows?(from => to)` - Check if specific transition is allowed
- `terminal?(state)` - Check if state has no outgoing transitions
- `states` - List all states in the system

### Layer 2: StateMachine (The Train)

The StateMachine executes transitions by triggering events within the rules defined by its TransitionSystem.

```ruby
machine = StateJacket::StateMachine.new(system, current_state: :draft)

# Define events and their transitions
machine.on :submit, :draft => :review
machine.on :approve, :review => :approved
machine.on :reject, :review => :rejected
machine.lock

# Execute transitions
result = machine.trigger(:submit)
```

**Key Methods:**

- `current_state` - Get current state
- `triggerable_events` - Events that can be triggered from current state
- `can_trigger?(event)` - Check if specific event can be triggered
- `finished?` - Check if machine is in a terminal state

### Why This Separation Matters

```ruby
# Easy to test transition rules independently
assert system.allows?(:draft => :review)
assert system.terminal?(:published)

# Easy to test event handling independently
assert machine.can_trigger?(:submit)
assert_equal "review", machine.trigger(:submit).to

# Easy to introspect and debug
puts "Available events: #{machine.triggerable_events}"
puts "Reachable states: #{machine.reachable_states}"
```

## Real-World Examples

### E-commerce Order Processing

```ruby
class OrderProcessor
  def initialize
    @system = build_transition_system
    @machine = StateJacket::StateMachine.new(@system, current_state: :cart)

    @machine.on :checkout, :cart => :submitted
    @machine.on :pay, :submitted => :paid
    @machine.on :cancel, [:cart, :submitted] => :cancelled
    @machine.on :ship, :paid => :shipped
    @machine.on :deliver, :shipped => :delivered
    @machine.lock
  end

  def checkout!(address:, payment_method:)
    return failure("Invalid address") unless valid_address?(address)
    return failure("Invalid payment") unless valid_payment?(payment_method)

    result = @machine.trigger(:checkout) do |from, to|
      # This block executes during the transition
      reserve_inventory
      @order_data = { address: address, payment_method: payment_method }
    end

    result.successful? ? success(result) : failure(result.error.message)
  end

  def process_payment!
    result = @machine.trigger(:pay) do |from, to|
      charge_payment(@order_data[:payment_method])
    end

    result.successful? ? success(result) : failure(result.error.message)
  end

  def state
    @machine.current_state
  end

  private

  def build_transition_system
    system = StateJacket::TransitionSystem.new
    system.add :cart => [:submitted, :cancelled]
    system.add :submitted => [:paid, :cancelled]
    system.add :paid => :shipped
    system.add :shipped => :delivered
    system.lock
  end

  def valid_address?(address)
    address && !address.empty?
  end

  def valid_payment?(payment_method)
    payment_method && !payment_method.empty?
  end

  def charge_payment(method)
    # Payment processing logic
    raise "Payment failed" if method == "invalid_card"
  end

  def reserve_inventory
    # Inventory reservation logic
  end

  def success(result)
    { success: true, state: @machine.current_state, result: result }
  end

  def failure(message)
    { success: false, state: @machine.current_state, error: message }
  end
end

# Usage
processor = OrderProcessor.new
result = processor.checkout!(
  address: "123 Main St",
  payment_method: "credit_card"
)

if result[:success]
  processor.process_payment!
  puts "Order state: #{processor.state}" # => "paid"
end
```

### User Account Lifecycle with Loops

```ruby
class UserAccountManager
  def initialize(user_id)
    @user_id = user_id
    @system = build_transition_system
    @machine = StateJacket::StateMachine.new(@system, current_state: :pending)

    @machine.on :activate, :pending => :active
    @machine.on :reject, :pending => :rejected
    @machine.on :suspend, :active => :suspended
    @machine.on :reactivate, :suspended => :active
    @machine.on :deactivate, [:active, :suspended] => :deactivated
    @machine.lock
  end

  def activate!
    result = @machine.trigger(:activate) do |from, to|
      track_activation
      send_welcome_email
    end

    result.successful? ? success : failure(result.error.message)
  end

  def suspend!(reason:)
    result = @machine.trigger(:suspend) do |from, to|
      log_suspension(reason)
      send_suspension_notice
    end

    result.successful? ? success : failure(result.error.message)
  end

  def state
    @machine.current_state
  end

  private

  def build_transition_system
    system = StateJacket::TransitionSystem.new
    system.add :pending => [:active, :rejected]
    system.add :active => [:suspended, :deactivated]
    system.add :suspended => [:active, :deactivated]  # Can reactivate
    system.lock
  end

  def track_activation
    puts "User #{@user_id} activated at #{Time.now}"
  end

  def send_welcome_email
    puts "Welcome email sent to user #{@user_id}"
  end

  def log_suspension(reason)
    puts "User #{@user_id} suspended: #{reason}"
  end

  def send_suspension_notice
    puts "Suspension notice sent to user #{@user_id}"
  end

  def success
    { success: true, state: state }
  end

  def failure(message)
    { success: false, error: message, state: state }
  end
end
```

## Pattern Matching (Ruby 3.x)

StateJacket provides first-class support for Ruby's pattern matching through `deconstruct_keys`.

### Machine State Matching

```ruby
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
```

### Transition Result Matching

```ruby
def handle_order_transition(result)
  case result
  in event: "submit", status: :ok then "Order submitted successfully"
  in event: "pay", status: :ok then "Payment processed successfully"
  in event: "pay", status: :error, error: then "Error during payment: #{error.message}"
  in status: :error, error: then "Error: #{error.message}"
  else "Unknown transition result"
  end
end
```

### Pattern Matching with Multiple Conditions

```ruby
def get_order_status(machine)
  case machine
  in current_state: "cart", triggerable_events: ["checkout"] then "Ready to checkout"
  in current_state: "submitted", finished: false then "Processing payment"
  in current_state: "shipped", reachable_states: ["delivered"] then "In transit"
  in finished: true then "Order complete"
  else "Status unknown"
  end
end
```
</thinking>

Let me look at the pattern matching examples more carefully and replace the complex one with something simpler and clearer.

<edits>

<old_text>
### Pattern Matching with Multiple Conditions

```ruby
def get_order_status(machine)
  case machine
  in current_state: "cart", triggerable_events: ["checkout"] then "Ready to checkout"
  in current_state: "submitted", finished: false then "Processing payment"
  in current_state: "shipped", reachable_states: ["delivered"] then "In transit"
  in finished: true then "Order complete"
  else "Status unknown"
  end
end
```

## Workflow Resumption

StateJacket supports pausing and resuming workflows across process boundaries - perfect for long-running processes that span days, weeks, or months.

### Simple Resumption with State Evolution

```ruby
# Day 1: Start workflow
system = StateJacket::TransitionSystem.new
system.add :draft => :review
system.add :review => [:approved, :rejected]
system.lock

machine = StateJacket::StateMachine.new(system, current_state: :draft)
machine.on :submit, :draft => :review
machine.lock

machine.trigger(:submit)
saved_state = machine.current_state # Save just the state to database

# Day 3: Resume workflow (potentially with evolved system)
evolved_system = StateJacket::TransitionSystem.new
evolved_system.add :draft => :review
evolved_system.add :review => [:approved, :rejected, :needs_revision] # Added new option
evolved_system.add :needs_revision => :review # Recovery path
evolved_system.lock

# Create new machine with saved state
machine = StateJacket::StateMachine.new(evolved_system, current_state: saved_state)
machine.on :approve, :review => :approved
machine.on :reject, :review => :rejected
machine.on :revise, :review => :needs_revision # New capability
machine.lock

machine.trigger(:approve) # Continue where we left off
```

### Full Serialization for Complex Workflows

```ruby
# For complex machines where you want to preserve all events and rules
machine_hash = machine.to_hash
system_hash = system.to_hash

# Store in database, Redis, etc.
save_to_database(machine_hash, system_hash)

# Later, restore complete state including all defined events
restored_system = StateJacket::TransitionSystem.from_hash(system_hash)
restored_machine = StateJacket::StateMachine.from_hash(restored_system, machine_hash)

# Machine is fully restored with all original events - ready to continue
puts restored_machine.triggerable_events # All original events preserved
restored_machine.trigger(:approve) # Works immediately
```

### When to Use Each Pattern

**Simple Resumption** - When you want flexibility to evolve your workflow:
```ruby
# Save minimal state
saved_state = machine.current_state

# Resume with potentially different system/events
new_machine = StateJacket::StateMachine.new(evolved_system, current_state: saved_state)
new_machine.on :new_event, :current_state => :new_target
```

**Full Serialization** - When you want to preserve exact workflow state:
```ruby
# Save complete state
machine_hash = machine.to_hash
system_hash = system.to_hash

# Restore exact same workflow
restored_machine = StateJacket::StateMachine.from_hash(
  StateJacket::TransitionSystem.from_hash(system_hash), 
  machine_hash
)
```

## Advanced Features

### Thread Safety

StateJacket is designed for concurrent access:

```ruby
system = build_shared_system.lock  # Immutable after locking

# Each thread gets its own machine instance
threads = 10.times.map do |i|
  Thread.new do
    machine = StateJacket::StateMachine.new(system, current_state: :pending)
    machine.on :process, :pending => :completed
    machine.lock

    machine.trigger(:process)
    puts "Thread #{i}: #{machine.current_state}"
  end
end

threads.each(&:join)
```

### Error Handling

Transition blocks can raise errors, which are captured in the result:

```ruby
result = machine.trigger(:pay) do |from, to|
  raise "Payment gateway timeout"
end

puts result.successful?     # => false
puts result.status          # => :error
puts result.error.message   # => "Payment gateway timeout"
puts machine.current_state  # => unchanged due to error
```

### Introspection

Rich introspection capabilities for debugging and monitoring:

```ruby
# Machine introspection
machine.current_state       # => "pending"
machine.events              # => ["approve", "reject"]
machine.triggerable_events  # => ["approve", "reject"]
machine.reachable_states    # => ["approved", "rejected"]
machine.finished?           # => false
machine.locked?             # => true

# System introspection
system.states              # => ["pending", "approved", "rejected"]
system.transitioners       # => ["pending"]
system.terminals           # => ["approved", "rejected"]
system.allows?(:pending => :approved)  # => true
system.terminal?(:approved)         # => true
```

## Testing

StateJacket's architecture makes testing straightforward by separating concerns.

### Testing Transition Systems

```ruby
class OrderTransitionsTest < Test
  def setup
    @system = StateJacket::TransitionSystem.new
    @system.add :cart => [:submitted, :abandoned]
    @system.add :submitted => [:paid, :cancelled]
    @system.add :paid => :shipped
    @system.add :shipped => :delivered
    @system.lock
  end

  def test_validates_legal_transitions
    assert @system.allows?(:cart => :submitted)
    assert @system.allows?(:submitted => :paid)
    assert @system.allows?(:paid => :shipped)
  end

  def test_rejects_illegal_transitions
    refute @system.allows?(:cart => :delivered)
    refute @system.allows?(:delivered => :cart)
  end

  def test_system_structure_matches_expectations
    assert_equal ["cart", "submitted", "abandoned", "paid", "cancelled", "shipped", "delivered"], @system.states
    assert_equal ["cart", "submitted", "paid", "shipped"], @system.transitioners
    assert_equal ["abandoned", "cancelled", "delivered"], @system.terminals
  end
end
```

### Testing State Machines

```ruby
class OrderStateMachineTest < Test
  def setup
    @system = build_order_system
    @machine = StateJacket::StateMachine.new(@system, current_state: :cart)
    @machine.on :checkout, :cart => :submitted
    @machine.on :pay, :submitted => :paid
    @machine.on :ship, :paid => :shipped
    @machine.lock
  end

  def test_transitions_on_valid_events
    assert_equal "cart", @machine.current_state

    result = @machine.trigger(:checkout)
    assert result.successful?
    assert_equal "submitted", @machine.current_state
  end

  def test_returns_failure_for_invalid_transitions
    # Try to trigger non-existent event
    assert_raises(ArgumentError) { @machine.trigger(:invalid_event) }
  end

  def test_machine_introspection_at_each_state
    # In cart state
    assert_equal ["checkout"], @machine.triggerable_events
    assert_equal ["submitted"], @machine.reachable_states
    refute @machine.finished?

    # Move to submitted
    @machine.trigger(:checkout)
    assert_equal ["pay"], @machine.triggerable_events
    assert_equal ["paid"], @machine.reachable_states
    refute @machine.finished?

    # Move to shipped (terminal)
    @machine.trigger(:pay)
    @machine.trigger(:ship)
    assert_equal [], @machine.triggerable_events
    assert_equal [], @machine.reachable_states
    assert @machine.finished?
  end
end
```

## Installation

Add to your Gemfile:

```ruby
gem 'state_jacket'
```

Or install directly:

```bash
gem install state_jacket
```

### Requirements

- Ruby 3.0 or higher (for pattern matching support)
- No external dependencies

## Migration from Other Libraries

### From AASM

**Before (AASM):**

```ruby
class Order
  include AASM

  aasm do
    state :pending, initial: true
    state :paid, :cancelled

    event :pay do
      transitions from: :pending, to: :paid, guard: :payment_valid?
    end

    event :cancel do
      transitions from: :pending, to: :cancelled
    end
  end

  private

  def payment_valid?
    # validation logic
  end
end
```

**After (StateJacket):**

```ruby
class Order
  def initialize
    @system = build_state_machine
    @machine = StateJacket::StateMachine.new(@system, current_state: :pending)
    @machine.on :pay, :pending => :paid
    @machine.on :cancel, :pending => :cancelled
    @machine.lock
  end

  def pay!
    return failure("Invalid payment") unless payment_valid?

    result = @machine.trigger(:pay) do |from, to|
      process_payment
    end

    result.successful? ? success(result) : failure(result.error.message)
  end

  def cancel!
    result = @machine.trigger(:cancel) do |from, to|
      notify_cancellation
    end

    result.successful? ? success(result) : failure(result.error.message)
  end

  def state
    @machine.current_state
  end

  private

  def build_state_machine
    system = StateJacket::TransitionSystem.new
    system.add :pending => [:paid, :cancelled]
    system.lock
  end

  def payment_valid?
    # validation logic
  end

  def process_payment
    # payment processing
  end

  def notify_cancellation
    # notification logic
  end

  def success(result)
    { success: true, state: state, result: result }
  end

  def failure(message)
    { success: false, error: message, state: state }
  end
end
```

### Key Migration Benefits

1. **Explicit Error Handling**: No more silent failures
2. **Better Testing**: Separate transition rules from event logic
3. **Workflow Resumption**: Built-in support for long-running processes
4. **Pattern Matching**: Modern Ruby 3.x features
5. **System Evolution**: Modify workflows without breaking existing state

## Performance

StateJacket is optimized for both memory efficiency and execution speed:

- **Memory**: Minimal object allocation, shared immutable systems
- **Speed**: O(1) transition lookups, cached introspection results
- **Concurrency**: Thread-safe design for high-concurrency applications

### Benchmarks

On a typical development machine:

- Transition execution: ~100,000 transitions/second
- System creation: ~10,000 systems/second
- Machine creation: ~50,000 machines/second

## Contributing

1. Fork the repository
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Add tests for your changes
4. Ensure all tests pass (`bundle exec rake test`)
5. Commit your changes (`git commit -am 'Add some feature'`)
6. Push to the branch (`git push origin my-new-feature`)
7. Create a Pull Request

### Development Setup

```bash
git clone https://github.com/your-username/state_jacket.git
cd state_jacket
bundle install
bundle exec rake test
```

## License

MIT License. See LICENSE file for details.

---

**StateJacket** - Because complex workflows deserve simple, powerful tools.
