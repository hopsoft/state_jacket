[![Lines of Code](http://img.shields.io/badge/lines_of_code-249-brightgreen.svg?style=flat)](http://blog.codinghorror.com/the-best-code-is-no-code-at-all/)
[![Maintainability](https://api.codeclimate.com/v1/badges/14c24e331928eca7c724/maintainability)](https://codeclimate.com/github/hopsoft/state_jacket/maintainability)
[![Build Status](https://github.com/hopsoft/state_jacket/actions/workflows/test.yml/badge.svg)](https://github.com/hopsoft/state_jacket/actions/workflows/test.yml)
[![Coverage Status](https://img.shields.io/coveralls/hopsoft/state_jacket.svg?style=flat)](https://coveralls.io/r/hopsoft/state_jacket?branch=master)
[![Downloads](http://img.shields.io/gem/dt/state_jacket.svg?style=flat)](http://rubygems.org/gems/state_jacket)

# StateJacket

**A modern Ruby state machine library with clean two-layer architecture, Ruby 3+ pattern matching, and exceptional performance.**

StateJacket eliminates state management headaches for Ruby developers by providing a lightweight, thread-safe state machine that keeps your application's logic clean, predictable, and easy to reason about and maintain.

<!-- toc -->

- [Quick Start](#quick-start)
- [Why StateJacket?](#why-statejacket)
- [Core Architecture](#core-architecture)
- [Real-World Examples](#real-world-examples)
- [Pattern Matching](#pattern-matching)
- [Migration Guide](#migration-guide)
- [Advanced Features](#advanced-features)
- [Performance & Production](#performance--production)
- [Testing](#testing)
- [Installation](#installation)
- [Requirements](#requirements)
- [Contributing](#contributing)
- [License](#license)

<!-- tocstop -->

## Quick Start

Get started with StateJacket in under 30 seconds:

```bash
# install the gem
gem install state_jacket
```

```ruby
require 'state_jacket'

# 1. Define valid state transitions (domain rules)
system = StateJacket::StateTransitionSystem.new
system.add :pending => [:approved, :rejected] # creates approved & rejected as terminals automatically
system.lock                                   # locks the system (prevents changes)

# inspect the system
system.to_h          # => {"approved" => nil, "rejected" => nil, "pending" => ["approved", "rejected"]}
system.states        # => ["approved", "rejected", "pending"]
system.terminators   # => ["approved", "rejected"]
system.transitioners # => ["pending"]

# 2. Create state machine with the initial state
machine = StateJacket::StateMachine.new(system, state: :pending)
machine.on :approve, :pending => :approved # :approve event transitions pending -> approved
machine.on :reject, :pending => :rejected  # :reject event transitions pending -> rejected
machine.lock                               # locks the machine (prevents changes)

# inspect the machine
machine.to_h               # => {"approve" => [{"pending" => "approved"}], "reject" => [{"pending" => "rejected"}]}
machine.events             # => ["approve", "reject"]
machine.triggerable_events # => ["approve", "reject"]
machine.states             # => ["approved", "rejected", "pending"]
machine.reachable_states   # => ["approved", "rejected"]

# 3. Trigger a transition
result = machine.trigger(:approve)

# inspect the machine
machine.state # => "approved"

# 4. Handle result (pattern matching)
case result
in success?: true, to: "approved" then puts "Approved!"
in failed?: true then puts "Approval failed!"
end
```

> [!NOTE] > **Automatic State Creation**
>
> StateJacket automatically creates terminal states when they're referenced as destinations. For example, `system.add pending: [:approved, :rejected]` creates `approved` and `rejected` as terminal states automatically - no need to add them explicitly unless they have outgoing transitions.

> [!NOTE]
>
> **Hash Rocket Syntax for Transitions**
>
> StateJacket supports both hash syntax styles, but we recommend hash rockets (`=>`) for state transitions because they visually represent directional flow: `pending => approved` clearly shows the transition direction, making state machine definitions more readable and intuitive.

### Understanding Your State Machine

StateJacket provides rich introspection to help you understand the structure and current state of your systems:

```ruby
# After running the basic example above, inspect what was created:

# Current state information
puts machine.state                   # => "approved"
puts machine.state_symbol            # => :approved
puts machine.terminal?               # => true

# What events are available?
puts machine.events                  # => ["approve", "reject"]
puts machine.triggerable_events     # => [] (none from terminal state)
puts machine.can_trigger? :approve   # => false (already approved)

# Where can we go from here?
puts machine.reachable_states        # => [] (terminal state)

# What did the system create automatically?
puts system.states                   # => ["approved", "rejected", "pending"]
puts system.transitioners           # => ["pending"] (states with outgoing transitions)
puts system.terminators             # => ["approved", "rejected"] (end states)

# Verify the business rules
puts system.can_transition? pending: :approved    # => true
puts system.can_transition? approved: :pending    # => false
puts system.locked?                               # => true

# Examine the complete structure
puts system.to_h
# => {"approved"=>nil, "rejected"=>nil, "pending"=>["approved", "rejected"]}

puts machine.to_h
# => {"approve"=>[{"pending"=>"approved"}], "reject"=>[{"pending"=>"rejected"}]}
```

This introspection is invaluable for debugging complex state machines and understanding what StateJacket created from your concise definitions.

## Why StateJacket?

### The Problem

Traditional state machines mix business rules with event handling, making them hard to test, debug, and maintain. They also typically suffer from performance issues and lack modern Ruby features.

### The Solution

StateJacket introduces a **two-layer architecture** that separates concerns:

1. **StateTransitionSystem** - Defines _what_ transitions are valid (domain rules)
2. **StateMachine** - Manages _how_ transitions happen (current state + events)

### Key Benefits

- [x] **Ruby 3+ pattern matching** - Handle transitions with elegant case/in expressions
- [x] **Clean architecture** - Separate domain rules from event logic
- [x] **Thread-safe by design** - Immutable after locking for concurrent access
- [x] **Exceptional performance** - 1.7M+ transitions/second with O(1) lookup complexity
- [x] **Zero dependencies** - Small bundle size, fast load time, no version conflicts
- [x] **Framework agnostic** - Works anywhere Ruby works (Rails, Sinatra, plain Ruby, etc.)
- [x] **Type safety** - Full RBS support for better development experience
- [x] **Superior debugging** - Rich introspection and clear error messages
- [x] **Explicit validation** - No hidden guard methods or callbacks
- [x] **Production ready** - Comprehensive error handling and graceful failures

### Compared to AASM/StateMachines

**StateJacket encourages explicit, testable code:**

```ruby
# Instead of hidden guard methods and callbacks...
case result
in success?: true, from: "pending", to: "approved"
  send_approval_notification       # explicit business logic
  update_inventory_status          # clear side effects
in failed?: true, from: state
  handle_validation_failure state  # explicit error handling
end
```

**Key advantages over traditional libraries:**

- Zero dependencies (vs. multiple gem dependencies)
- Explicit validation over implicit guards (more testable)
- Superior performance characteristics (O(1) vs O(n) lookups)
- Modern Ruby 3+ features (pattern matching, rightward assignment)
- Clean separation of concerns (business rules vs. event logic)
- No magic callbacks or hidden behavior (explicit > implicit)
- Framework agnostic (works everywhere Ruby works)
- Better debugging experience (rich introspection)

### Developer Experience

StateJacket prioritizes developer productivity and maintainability:

- **Fast feedback loop** - Immediate validation errors with helpful messages
- **Rich introspection** - Inspect states, events, and transitions at runtime
- **Minimal API surface** - Small, focused API that's easy to learn and remember
- **No magic** - Explicit behavior, no hidden callbacks or surprise side effects
- **Easy testing** - Separation of concerns makes unit testing straightforward
- **Migration friendly** - Simple patterns for migrating from any state machine library
- **Documentation** - Comprehensive examples and clear architectural guidance

## Core Architecture

### Understanding the Layers

Think of StateJacket like a **railway system**:

#### Layer 1: StateTransitionSystem (The Railway Network)

Defines the **tracks and stations** - what routes are physically possible.

```ruby
# Define the railway network (domain rules)
system = StateJacket::StateTransitionSystem.new
system.add station_a: [:station_b, :station_c]  # routes from station A
system.add station_b: :station_c                 # routes from station B (station_c auto-created as terminal)
system.lock
```

#### Layer 2: StateMachine (The Train)

Manages the **current location and movement** - where you are and how you travel.

```ruby
# Create a train on the network
machine = StateJacket::StateMachine.new(system, state: :station_a)
machine.on :express_route, station_a: :station_c  # express train event
machine.on :local_route, station_a: :station_b    # local train event
machine.on :continue, station_b: :station_c       # continuation event
machine.lock
```

### Why This Separation Matters

1. **Independent Testing** - Test railway routes separately from train operations
2. **Reusable Infrastructure** - Same railway network, multiple trains
3. **Clear Responsibilities** - Infrastructure vs. operations are distinct

### Flexible Event Syntax

StateJacket supports multiple syntaxes for defining transitions:

```ruby
# Single source transition
machine.on :approve, pending: :approved

# Multiple source transitions (hash syntax)
machine.on :archive, draft: :archived, published: :archived

# Multiple source transitions (array syntax - cleaner)
machine.on :archive, [:draft, :published] => :archived
```

## Real-World Examples

### E-commerce Order Processing

<details>
<summary><strong>Start Simple</strong> - Basic order workflow</summary>

```ruby
# Define the state transitions (domain rules)
system = StateJacket::StateTransitionSystem.new
system.add cart: [:submitted, :abandoned]
system.add submitted: [:paid, :cancelled]
system.add paid: :shipped
system.add shipped: :delivered  # delivered auto-created as terminal
system.lock                     # cancelled & abandoned also auto-created as terminals

# Create the state machine (current state + event behavior)
machine = StateJacket::StateMachine.new(system, state: :cart)
machine.on :submit, cart: :submitted
machine.on :pay, submitted: :paid
machine.on :ship, paid: :shipped
machine.on :deliver, shipped: :delivered
machine.on :abandon, cart: :abandoned
machine.on :cancel, submitted: :cancelled
machine.lock

# Inspect what StateJacket created from our concise definitions:
puts "States created: #{system.states}"
# => ["submitted", "abandoned", "cart", "paid", "cancelled", "shipped", "delivered"]

puts "Active states: #{system.transitioners}"
# => ["submitted", "cart", "paid", "shipped"]

puts "Terminal states: #{system.terminators}"
# => ["abandoned", "cancelled", "delivered"]

puts "From cart, you can: #{machine.triggerable_events}"
# => ["submit", "abandon"]

puts "System structure:"
puts system.to_h
# => {
#   "submitted" => ["paid", "cancelled"],
#   "abandoned" => nil,
#   "cart" => ["submitted", "abandoned"],
#   "paid" => ["shipped"],
#   "cancelled" => nil,
#   "shipped" => ["delivered"],
#   "delivered" => nil
# }
```

</details>

<details>
<summary><strong>Add Business Logic</strong> - Handle transitions with validation and introspection</summary>

```ruby
class OrderProcessor
  def initialize(order)
    @order = order
    @machine = build_machine
  end

  def checkout!
    return failure("Cart is empty") if @order.items.empty?
    return failure("Invalid address") unless valid_address?

    result = @machine.trigger(:checkout)
    case result
    in success?: true, to: "submitted"
      OrderMailer.confirmation_email(@order).deliver_now
      success "Order submitted successfully"
    in failed?: true
      failure "Unable to submit order"
    end
  end

  def process_payment!(payment_method)
    return failure("Invalid payment method") unless valid_payment? payment_method

    result = @machine.trigger(:payment) do |from, to|
      charge_payment payment_method  # business logic in block
      reserve_inventory              # explicit side effects
    end

    case result
    in success?: true, to: "paid"
      success "Payment processed"
    in failed?: true
      failure "Payment failed"
    end
  end

  def state
    @machine.state
  end

  private

  def build_machine
    system = StateJacket::StateTransitionSystem.new
    system.add cart: [:submitted, :abandoned]
    system.add submitted: [:paid, :cancelled]
    system.add paid: [:shipped, :refunded]
    system.add shipped: [:delivered, :returned]  # all destination states auto-created as terminals
    system.lock

    machine = StateJacket::StateMachine.new(system, state: @order.status)
    machine.on :checkout, cart: :submitted
    machine.on :payment, submitted: :paid
    machine.on :ship, paid: :shipped
    machine.on :deliver, shipped: :delivered
    machine.on :abandon, cart: :abandoned
    machine.on :cancel, submitted: :cancelled
    machine.on :refund, [:paid, :shipped, :delivered] => :refunded
    machine.lock
    machine
  end

  # Debug helper to understand the system structure
  def inspect_system
    puts "=== Order System Analysis ==="
    puts "Current state: #{@machine.state}"
    puts "Available actions: #{@machine.triggerable_events}"
    puts "Next possible states: #{@machine.reachable_states}"
    puts "Is terminal state?: #{@machine.terminal?}"

    puts "\n=== System Structure ==="
    puts "All states: #{@machine.states}"
    puts "Terminal states: #{@machine.transition_system.terminators}"
    puts "Active states: #{@machine.transition_system.transitioners}"

    puts "\n=== Complete Event Map ==="
    @machine.to_h.each do |event, transitions|
      puts "#{event}: #{transitions}"
    end
  end

  def valid_address?
    @order.shipping_address&.complete?
  end

  def valid_payment?(payment_method)
    payment_method&.valid? && payment_method.sufficient_funds?(@order.total)
  end

  def charge_payment(payment_method)
    PaymentService.charge payment_method, @order.total
  end

  def reserve_inventory
    @order.items.each { |item| InventoryService.reserve item }
  end

  def success(message)
    { success: true, message: message }
  end

  def failure(message)
    { success: false, error: message }
  end
end
```

</details>

<details>
<summary><strong>Debugging Complex Systems</strong> - Use introspection to understand your state machine</summary>

```ruby
# Complex order processing with refunds, returns, and error states
system = StateJacket::StateTransitionSystem.new
system.add cart: [:submitted, :abandoned]
system.add submitted: [:paid, :cancelled]
system.add paid: [:shipped, :refunded]
system.add shipped: [:delivered, :returned, :lost]
system.add delivered: [:completed, :returned]
system.add returned: [:refunded, :restocked]
system.add refunded: :completed
system.add restocked: [:resold, :disposed]
system.add lost: [:refunded, :replaced]
system.lock

machine = StateJacket::StateMachine.new(system, state: :cart)
machine.on :submit, cart: :submitted
machine.on :pay, submitted: :paid
machine.on :ship, paid: :shipped
machine.on :deliver, shipped: :delivered
machine.on :complete, delivered: :completed
machine.on :return, [:shipped, :delivered] => :returned
machine.on :refund, [:paid, :returned, :lost] => :refunded
machine.on :restock, returned: :restocked
machine.on :lose, shipped: :lost
machine.on :replace, lost: :shipped
machine.on :resell, restocked: :paid  # back into the system
machine.lock

# Let's inspect this complex system:
puts "=== Ultra Complex Order System Analysis ==="
puts "Total states: #{system.states.count}"      # => 15
puts "States: #{system.states}"
# => ["submitted", "abandoned", "cart", "paid", "cancelled", "shipped", "refunded",
#     "delivered", "returned", "lost", "completed", "restocked", "resold", "disposed", "replaced"]

puts "\nStates that can transition elsewhere:"
system.transitioners.each do |state|
  destinations = system.to_h[state]
  puts "  #{state} → #{destinations}"
end
# =>  submitted → ["paid", "cancelled"]
#     cart → ["submitted", "abandoned"]
#     paid → ["shipped", "refunded"]
#     shipped → ["delivered", "returned", "lost"]
#     refunded → ["completed"]
#     delivered → ["completed", "returned"]
#     returned → ["refunded", "restocked"]
#     lost → ["refunded", "replaced"]
#     restocked → ["resold", "disposed"]

puts "\nEnd states (no outgoing transitions):"
puts "  #{system.terminators}"
# => ["abandoned", "cancelled", "completed", "resold", "disposed", "replaced"]

puts "\nFrom 'shipped', possible paths:"
machine = StateJacket::StateMachine.new(system, state: :shipped)
machine.on :deliver, shipped: :delivered
machine.on :return, shipped: :returned
machine.on :lose, shipped: :lost
machine.lock

puts "  Available actions: #{machine.triggerable_events}"   # => ["deliver", "return", "lose"]
puts "  Possible destinations: #{machine.reachable_states}" # => ["delivered", "returned", "lost"]

# Verify complex business rules:
puts "\nBusiness rule validation:"
puts "  Can cart go directly to shipped?: #{system.can_transition? cart: :shipped}"        # => false
puts "  Can returned items be restocked?: #{system.can_transition? returned: :restocked}" # => true
puts "  Can restocked items be resold?: #{system.can_transition? restocked: :resold}"     # => true
puts "  Are completed orders terminal?: #{system.terminators.include?('completed')}"       # => true
```

</details>

### User Account Lifecycle

<details>
<summary><strong>Account Management</strong> - User registration and moderation</summary>

```ruby
class UserAccountManager
  def initialize(user)
    @user = user
    @machine = build_machine
  end

  def activate!
    return failure("Email not verified") unless @user.email_verified?
    return failure("Profile incomplete") unless @user.profile_complete?

    result = @machine.trigger(:activate) do |from, to|
      @user.update! activated_at: Time.current
      UserMailer.welcome(@user).deliver_now
      track_activation
    end

    case result
    in success?: true
      success "Account activated successfully"
    in failed?: true
      failure "Unable to activate account"
    end
  end

  def suspend!(reason)
    result = @machine.trigger(:suspend) do |from, to|
      @user.update! suspended_at: Time.current, suspension_reason: reason
      UserMailer.suspension_notice(@user, reason).deliver_now
    end

    case result
    in success?: true
      success "Account suspended"
    in failed?: true
      failure "Unable to suspend account"
    end
  end

  def state
    @machine.state
  end

  private

  def build_machine
    system = StateJacket::StateTransitionSystem.new
    system.add pending: [:active, :rejected]
    system.add active: [:suspended, :deactivated]
    system.add suspended: [:active, :deactivated]
    system.add deactivated: :active  # rejected auto-created as terminal from first transition
    system.lock

    machine = StateJacket::StateMachine.new(system, state: @user.status)
    machine.on :activate, pending: :active
    machine.on :reject, pending: :rejected
    machine.on :suspend, active: :suspended
    machine.on :deactivate, [:active, :suspended] => :deactivated
    machine.on :reactivate, [:suspended, :deactivated] => :active
    machine.lock
    machine
  end

  def track_activation
    Analytics.track(@user.id, 'Account Activated')
  end

  def success(message)
    { success: true, message: message }
  end

  def failure(message)
    { success: false, error: message }
  end
end
```

</details>

## Pattern Matching

StateJacket provides comprehensive Ruby 3+ pattern matching support for elegant transition handling.

### Machine State Matching

Match on current state and available actions:

```ruby
def handle_order_state(machine)
  case machine
  in state: "pending", actions: events if events.include?("approve")
    render_approval_form
  in state: "approved", destinations: ["completed"]
    render_completion_button
  in terminal?: true
    render_final_status
  else
    render_default_view
  end
end
```

### Transition Result Matching

Handle transition outcomes with precise pattern matching:

```ruby
def handle_order_transition(result)
  case result
  in success?: true, from: "pending", to: "approved", event: "approve"
    send_approval_notification
    update_inventory_status
  in success?: true, from: "pending", to: "rejected", event: "reject"
    send_rejection_notification
    log_rejection_reason
  in failed?: true, from: "pending", event: event_name
    handle_transition_failure(event_name)
  end
end
```

### Pattern Matching with Guard Clauses

Combine patterns with business logic:

```ruby
def determine_user_permissions(machine)
  case machine
  in state: "pending", actions: events if events.include?("activate")
    [:view_profile, :complete_verification]
  in state: "active", reachable_states: states if states.include?("premium")
    [:read, :write, :comment, :upgrade_to_premium]
  in state: "premium", terminal?: false
    [:read, :write, :comment, :moderate, :export_data]
  in terminal?: true
    [:view_profile]
  else
    []
  end
end
```

### Built-in Pattern Classes

StateJacket provides pattern classes for common scenarios:

```ruby
# Transition result patterns
case result
when StateJacket::Patterns::Success
  handle_success
when StateJacket::Patterns::Failure
  handle_failure
when StateJacket::Patterns::StateChange
  log_state_change
end

# Machine state patterns
case machine
when StateJacket::StateMachine::Patterns::Terminal
  show_completed_status
when StateJacket::StateMachine::Patterns::Active
  show_action_buttons
when StateJacket::StateMachine::Patterns::PendingAction[:approve]
  show_approval_form
end
```

## Migration Guide

### From AASM

<details>
<summary><strong>Basic Migration</strong> - Converting AASM state machines</summary>

**AASM:**

```ruby
class Order
  include AASM

  aasm column: :state do
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
    payment_method.present? && payment_method.valid?
  end
end
```

```ruby
class Order
  def initialize
    @machine = build_state_machine
  end

  def pay!
    return failure("Invalid payment") unless payment_valid?

    result = @machine.trigger(:pay) do |from, to|
      self.state = to
      process_payment
    end

    case result
    in success?: true
      success "Payment processed"
    in failed?: true
      failure "Payment failed"
    end
  end

  def cancel!
    result = @machine.trigger(:cancel) do |from, to|
      self.state = to
      notify_cancellation
    end

    case result
    in success?: true
      success "Order cancelled"
    in failed?: true
      failure "Cannot cancel order"
    end
  end

  def state
    @machine.state
  end

  private

  def build_state_machine
    system = StateJacket::StateTransitionSystem.new
    system.add pending: [:paid, :cancelled]  # paid & cancelled auto-created as terminals
    system.lock

    machine = StateJacket::StateMachine.new(system, state: :pending)
    machine.on :pay, pending: :paid
    machine.on :cancel, pending: :cancelled
    machine.lock
    machine
  end

  def payment_valid?
    payment_method.present? && payment_method.valid?
  end

  def process_payment
    PaymentService.charge(payment_method, amount)
  end

  def notify_cancellation
    OrderMailer.cancellation_notice(self).deliver_now
  end

  def success(message)
    { success: true, message: message }
  end

  def failure(message)
    { success: false, error: message }
  end
end
```

</details>

### Key Differences Summary

| Aspect               | AASM/StateMachines | StateJacket                  |
| -------------------- | ------------------ | ---------------------------- |
| **Validation**       | Implicit guards    | Explicit validation methods  |
| **Callbacks**        | Built-in hooks     | Block-based callbacks        |
| **Architecture**     | Single-layer       | Two-layer (rules + behavior) |
| **Pattern Matching** | Not supported      | Full Ruby 3+ support         |
| **Performance**      | O(n) lookups       | O(1) lookups                 |
| **Thread Safety**    | Varies             | Safe after locking           |

## Advanced Features

### Thread Safety

StateJacket becomes immutable after locking, making it safe for concurrent access:

```ruby
# Safe to share across threads after locking
machine.lock
threads = 10.times.map do
  Thread.new do
    1000.times do
      machine.can_trigger? :approve  # Safe concurrent reads
      machine.state                  # Safe concurrent reads
    end
  end
end
threads.each(&:join)
```

### State Machine Introspection

Rich introspection capabilities for debugging and UI generation:

```ruby
# Let's build a more complex system to demonstrate introspection
system = StateJacket::StateTransitionSystem.new
system.add draft: [:review, :archived]
system.add review: [:published, :rejected, :archived]
system.add published: [:archived, :featured]
system.add rejected: :draft  # allows resubmission
system.lock

machine = StateJacket::StateMachine.new(system, state: :draft)
machine.on :submit, draft: :review
machine.on :approve, review: :published
machine.on :reject, review: :rejected
machine.on :archive, [:draft, :review, :published] => :archived
machine.on :feature, published: :featured
machine.on :revise, rejected: :draft
machine.lock

# Comprehensive introspection from draft state:
puts "=== Current State Analysis ==="
puts "State: #{machine.state}"                    # => "draft"
puts "Terminal?: #{machine.terminal?}"             # => false
puts "Available actions: #{machine.triggerable_events}"  # => ["submit", "archive"]
puts "Reachable states: #{machine.reachable_states}"     # => ["review", "archived"]

# System-wide analysis:
puts "\n=== System Structure ==="
puts "All states: #{system.states}"               # => ["review", "archived", "draft", "published", "rejected", "featured"]
puts "Active states: #{system.transitioners}"     # => ["review", "draft", "published", "rejected"]
puts "End states: #{system.terminators}"          # => ["archived", "featured"]

# Transition validation:
puts "\n=== Business Rules Validation ==="
puts "Can draft be published directly?: #{system.can_transition? draft: :published}"  # => false
puts "Can published be featured?: #{system.can_transition? published: :featured}"     # => true
puts "Can archived transition?: #{system.can_transition? archived: :draft}"           # => false

# Complete system mapping:
puts "\n=== Complete System Map ==="
puts system.to_h
# => {
#   "review" => ["published", "rejected", "archived"],
#   "archived" => nil,
#   "draft" => ["review", "archived"],
#   "published" => ["archived", "featured"],
#   "rejected" => ["draft"],
#   "featured" => nil
# }

puts "\n=== Event Mapping ==="
puts machine.to_h
# => {
#   "submit" => [{"draft" => "review"}],
#   "approve" => [{"review" => "published"}],
#   "reject" => [{"review" => "rejected"}],
#   "archive" => [{"draft" => "archived"}, {"review" => "archived"}, {"published" => "archived"}],
#   "feature" => [{"published" => "featured"}],
#   "revise" => [{"rejected" => "draft"}]
# }
```

This introspection becomes essential when building complex workflows - you can verify that your concise state definitions created exactly the state machine you intended.

## Performance & Production

StateJacket delivers exceptional performance through intelligent design:

- **1.7M+ transitions/second** - State machine mechanics are never your bottleneck
- **O(1) transition lookups** - Performance stays consistent as complexity grows
- **Memory efficient** - Frozen data structures with pre-computed caches
- **Thread-safe** - No synchronization overhead after locking

StateJacket's minimal overhead means you can focus entirely on your business logic rather than worrying about state machine performance. Whether you're processing thousands of orders per minute or managing complex workflow orchestrations, StateJacket scales with your application needs.

### Real-World Performance

Benchmark results demonstrate StateJacket's minimal overhead:

```
$ bin/benchmark
StateJacket Performance Benchmark
==================================================

Performing 1,000 total transitions:
  Completed in: 0.0006 seconds
  Rate: 1,763,669 transitions/second

Performing 10,000 total transitions:
  Completed in: 0.0064 seconds
  Rate: 1,559,090 transitions/second

Performing 100,000 total transitions:
  Completed in: 0.0588 seconds
  Rate: 1,701,085 transitions/second

Performing 1,000,000 total transitions:
  Completed in: 0.5817 seconds
  Rate: 1,719,223 transitions/second

==================================================
Benchmark completed successfully!
```

> **Run your own benchmarks**: `bin/benchmark` is included with StateJacket
>
> The consistent ~1.7M transitions/second rate across different workload sizes confirms true O(1) performance characteristics - StateJacket scales linearly with your business logic, not your state machine complexity.
>
> **Production Ready**: These performance characteristics make StateJacket suitable for high-throughput applications including payment processing, order fulfillment, and real-time workflow management.

## Testing

### Testing State Transition Systems

Test business rules independently with introspection for debugging:

```ruby
class OrderTransitionsTest < Minitest::Test
  def setup
    @system = StateJacket::StateTransitionSystem.new
    @system.add pending: [:processing, :cancelled]
    @system.add processing: [:completed, :failed]  # terminals auto-created
    @system.lock

    # Use introspection to verify what we built
    puts "System created: #{@system.states}"
    # => ["pending", "processing", "completed", "cancelled", "failed"]
    puts "Transitioners: #{@system.transitioners}"
    # => ["pending", "processing"]
    puts "Terminals: #{@system.terminators}"
    # => ["completed", "cancelled", "failed"]
  end

  def test_validates_legal_transitions
    assert @system.can_transition? pending: :processing
    assert @system.can_transition? processing: :completed

    # Debug failing tests with introspection
    unless @system.can_transition? pending: :completed
      puts "Direct pending→completed blocked. Valid from pending: #{@system.to_h['pending']}"
    end
  end

  def test_rejects_illegal_transitions
    refute @system.can_transition? completed: :pending

    # Verify why this should fail
    assert @system.terminators.include?("completed"), "completed should be terminal"
    assert_nil @system.to_h["completed"], "completed should have no outgoing transitions"
  end

  def test_system_structure_matches_expectations
    # Use introspection to verify the complete system structure
    expected_structure = {
      "pending" => ["processing", "cancelled"],
      "processing" => ["completed", "failed"],
      "completed" => nil,
      "cancelled" => nil,
      "failed" => nil
    }

    assert_equal expected_structure, @system.to_h

    # Verify counts
    assert_equal 5, @system.states.count
    assert_equal 2, @system.transitioners.count
    assert_equal 3, @system.terminators.count
  end
end
```

### Testing State Machines

Test event logic separately with debugging introspection:

```ruby
class OrderStateMachineTest < Minitest::Test
  def setup
    @machine = build_order_machine

    # Debug the machine setup
    puts "Machine events: #{@machine.events}"
    # => ["process", "complete"]
    puts "From pending: #{@machine.triggerable_events}"
    # => ["process"]
    puts "Event mapping: #{@machine.to_h}"
    # => {"process"=>[{"pending"=>"processing"}], "complete"=>[{"processing"=>"completed"}]}
  end

  def test_transitions_on_valid_events
    # Verify state before transition
    assert_equal "pending", @machine.state
    assert_includes @machine.triggerable_events, "process"
    assert_includes @machine.reachable_states, "processing"

    result = @machine.trigger(:process)
    assert result.success?
    assert_equal "processing", @machine.state

    # Verify state after transition
    assert_includes @machine.triggerable_events, "complete"
    assert_includes @machine.reachable_states, "completed"
    refute_includes @machine.triggerable_events, "process"
  end

  def test_returns_failure_for_invalid_transitions
    # Use introspection to understand why this should fail
    refute @machine.can_trigger?(:complete), "complete should not be available from pending"
    refute_includes @machine.triggerable_events, "complete"

    result = @machine.trigger(:complete)  # Can't complete from pending
    assert result.failed?
    assert_equal "pending", @machine.state  # State unchanged

    # Verify machine state is consistent after failed transition
    assert_equal ["process"], @machine.triggerable_events
  end

  def test_machine_introspection_at_each_state
    # Test introspection throughout the workflow
    states_analysis = {}

    # From pending
    states_analysis[:pending] = {
      triggerable: @machine.triggerable_events.dup,
      reachable: @machine.reachable_states.dup,
      terminal: @machine.terminal?
    }

    @machine.trigger(:process)

    # From processing
    states_analysis[:processing] = {
      triggerable: @machine.triggerable_events.dup,
      reachable: @machine.reachable_states.dup,
      terminal: @machine.terminal?
    }

    @machine.trigger(:complete)

    # From completed
    states_analysis[:completed] = {
      triggerable: @machine.triggerable_events.dup,
      reachable: @machine.reachable_states.dup,
      terminal: @machine.terminal?
    }

    # Verify the analysis
    assert_equal ["process"], states_analysis[:pending][:triggerable]
    assert_equal ["complete"], states_analysis[:processing][:triggerable]
    assert_equal [], states_analysis[:completed][:triggerable]
    assert states_analysis[:completed][:terminal]

    puts "State analysis: #{states_analysis}"
  end

  private

  def build_order_machine
    system = StateJacket::StateTransitionSystem.new
    system.add pending: [:processing, :cancelled]
    system.add processing: [:completed, :failed]  # completed, cancelled & failed auto-created as terminals
    system.lock

    machine = StateJacket::StateMachine.new(system, state: :pending)
    machine.on :process, pending: :processing
    machine.on :complete, processing: :completed
    machine.lock
    machine
  end
end
```

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'state_jacket'
```

And then execute:

```bash
bundle install
```

Or install it yourself as:

```bash
gem install state_jacket
```

### Test Performance

After installation, you can immediately test StateJacket's performance:

```bash
# Clone the repository to access benchmark script
git clone https://github.com/hopsoft/state_jacket.git
cd state_jacket
bin/benchmark
```

This will run performance tests showing StateJacket's 1.7M+ transitions/second capability.

## Requirements

- Ruby 3.0+ (for pattern matching features)
- No external dependencies

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/user/state_jacket.

### Development Setup

```bash
git clone https://github.com/user/state_jacket.git
cd state_jacket
bundle install
bundle exec rake test
```

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).

---

**StateJacket** - State machines that don't get in your way.
