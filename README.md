[![Lines of Code](http://img.shields.io/badge/lines_of_code-193-brightgreen.svg?style=flat)](http://blog.codinghorror.com/the-best-code-is-no-code-at-all/)
[![Maintainability](https://api.codeclimate.com/v1/badges/14c24e331928eca7c724/maintainability)](https://codeclimate.com/github/hopsoft/state_jacket/maintainability)
[![Build Status](https://github.com/hopsoft/state_jacket/actions/workflows/test.yml/badge.svg)](https://github.com/hopsoft/state_jacket/actions/workflows/test.yml)
[![Coverage Status](https://img.shields.io/coveralls/hopsoft/state_jacket.svg?style=flat)](https://coveralls.io/r/hopsoft/state_jacket?branch=master)
[![Downloads](http://img.shields.io/gem/dt/state_jacket.svg?style=flat)](http://rubygems.org/gems/state_jacket)

# StateJacket

**A modern Ruby state machine library with clean two-layer architecture, Ruby 3+ pattern matching, and exceptional performance.**

<!-- toc -->

- [Why StateJacket?](#why-statejacket)
- [Quick Start](#quick-start)
- [Core Concepts](#core-concepts)
- [Real-World Examples](#real-world-examples)
- [Pattern Matching](#pattern-matching)
- [Migration Guide](#migration-guide)
- [Advanced Features](#advanced-features)
- [Performance & Production](#performance--production)
- [Testing](#testing)
- [Installation](#installation-1)
- [Requirements](#requirements)
- [Contributing](#contributing)
- [License](#license)

<!-- tocstop -->

## Why StateJacket?

### For Modern Ruby Applications

✅ **Ruby 3+ pattern matching** - Handle transitions with elegant case/in expressions
✅ **Clean architecture** - Separate business rules from event logic
✅ **Thread-safe by design** - Immutable after locking for concurrent access
✅ **O(1) performance** - Consistent speed regardless of complexity
✅ **Type safety** - Full RBS support for better development experience

### Compared to AASM/StateMachines

**StateJacket encourages explicit, testable code:**

```ruby
# Instead of hidden guard methods...
case result
in { success?: true, from: "pending", to: "approved" }
  send_approval_notification
  update_inventory_status
in { failed?: true, from: state }
  handle_validation_failure(state)
end
```

**Key advantages:**

- Explicit validation over implicit guards (more testable)
- Superior performance characteristics
- Modern Ruby 3+ features
- Clean separation of concerns

## Quick Start

### Installation

```bash
gem install state_jacket
```

### Basic Usage

```ruby
require 'state_jacket'

# 1. Define business rules (what transitions are valid)
system = StateJacket::StateTransitionSystem.new
system.add(pending: [:approved, :rejected])
system.add(:approved)  # terminal state
system.add(:rejected)  # terminal state
system.lock

# 2. Create state machine (current state + event behavior)
machine = StateJacket::StateMachine.new(system, state: :pending)
machine.on :approve, pending: :approved
machine.on :reject, pending: :rejected
machine.lock

# 3. Use with pattern matching
result = machine.trigger(:approve)
case result
in { success?: true, to: "approved" }
  puts "Approved! 🎉"
in { failed?: true }
  puts "Approval failed"
end

puts machine.state  # => "approved"
```

### Key Methods

```ruby
# State machine introspection
machine.state                    # => "approved"
machine.events                   # => ["approve", "reject"]
machine.can_trigger?(:approve)   # => false (already approved)
machine.terminal?                # => true

# Transition system introspection
system.states                    # => ["pending", "approved", "rejected"]
system.can_transition?(pending: :approved)  # => true
```

## Core Concepts

### The Two-Layer Architecture

StateJacket's key innovation is separating **business rules** from **behavior**:

#### Layer 1: StateTransitionSystem (Business Rules)

Defines _what_ transitions are valid - your domain's fundamental rules.

```ruby
system = StateJacket::StateTransitionSystem.new
system.add(draft: [:review, :archived])
system.add(review: [:published, :draft])
system.add(published: [:archived])
system.add(:archived)  # terminal
system.lock
```

#### Layer 2: StateMachine (Behavior)

Manages _how_ transitions happen - current state and events.

```ruby
machine = StateJacket::StateMachine.new(system, state: :draft)
machine.on :submit, draft: :review
machine.on :publish, review: :published
machine.on :archive, [:draft, :published] => :archived
machine.lock
```

### Benefits of This Separation

1. **Independent testing** - Test business rules separately from event logic
2. **Reusable rules** - Same transition system, multiple machines
3. **Clear responsibilities** - Rules vs. behavior are distinct concerns

### Elegant Event Syntax

StateJacket supports multiple syntaxes for defining transitions:

```ruby
# Single source transition
machine.on :approve, pending: :approved

# Multiple source transitions (hash syntax)
machine.on :archive, {draft: :archived, published: :archived}

# Multiple source transitions (array syntax - more elegant)
machine.on :archive, [:draft, :published] => :archived
```

## Real-World Examples

### E-commerce Order Processing

<details>
<summary><strong>Start Simple</strong> - Basic order workflow</summary>

```ruby
# Define the business rules
system = StateJacket::StateTransitionSystem.new
system.add(cart: [:submitted, :abandoned])
system.add(submitted: [:paid, :cancelled])
system.add(paid: [:shipped])
system.add(shipped: [:delivered])
system.add(:delivered, :cancelled, :abandoned)  # terminal states
system.lock

# Create the state machine
machine = StateJacket::StateMachine.new(system, state: :cart)
machine.on :checkout, cart: :submitted
machine.on :payment, submitted: :paid
machine.on :ship, paid: :shipped
machine.on :deliver, shipped: :delivered
machine.on :cancel, [:cart, :submitted] => :cancelled
machine.lock
```

</details>

<details>
<summary><strong>Add Business Logic</strong> - Handle transitions with validation</summary>

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
    in { success?: true, to: "submitted" }
      OrderMailer.confirmation_email(@order).deliver_now
      success("Order submitted successfully")
    in { failed?: true }
      failure("Unable to submit order")
    end
  end

  def process_payment!(payment_method)
    return failure("Invalid payment method") unless valid_payment?(payment_method)

    result = @machine.trigger(:payment) do |from, to|
      charge_payment(payment_method)
      reserve_inventory
    end

    case result
    in { success?: true, to: "paid" }
      success("Payment processed")
    in { failed?: true }
      failure("Payment failed")
    end
  end

  def state
    @machine.state
  end

  private

  def build_machine
    system = StateJacket::StateTransitionSystem.new
    system.add(cart: [:submitted, :abandoned])
    system.add(submitted: [:paid, :cancelled])
    system.add(paid: [:shipped, :refunded])
    system.add(shipped: [:delivered, :returned])
    system.add(:delivered, :cancelled, :abandoned, :refunded, :returned)
    system.lock

    machine = StateJacket::StateMachine.new(system, state: @order.status)
    machine.on :checkout, cart: :submitted
    machine.on :payment, submitted: :paid
    machine.on :ship, paid: :shipped
    machine.on :deliver, shipped: :delivered
    machine.on :cancel, [:cart, :submitted] => :cancelled
    machine.on :refund, [:paid, :shipped, :delivered] => :refunded
    machine.lock
    machine
  end

  def valid_address?
    @order.shipping_address&.complete?
  end

  def valid_payment?(payment_method)
    payment_method&.valid? && payment_method.sufficient_funds?(@order.total)
  end

  def charge_payment(payment_method)
    PaymentService.charge(payment_method, @order.total)
  end

  def reserve_inventory
    @order.items.each { |item| InventoryService.reserve(item) }
  end

  def success(message)
    { success: true, message: message }
  end

  def failure(message)
    @machine.trigger(:fail) if @machine.can_trigger?(:fail)
    { success: false, error: message }
  end
end
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
      @user.update!(activated_at: Time.current)
      UserMailer.welcome(@user).deliver_now
      track_activation
    end

    case result
    in { success?: true }
      success("Account activated successfully")
    in { failed?: true }
      failure("Unable to activate account")
    end
  end

  def suspend!(reason)
    result = @machine.trigger(:suspend) do |from, to|
      @user.update!(suspended_at: Time.current, suspension_reason: reason)
      UserMailer.suspension_notice(@user, reason).deliver_now
    end

    case result
    in { success?: true }
      success("Account suspended")
    in { failed?: true }
      failure("Unable to suspend account")
    end
  end

  def state
    @machine.state
  end

  private

  def build_machine
    system = StateJacket::StateTransitionSystem.new
    system.add(pending: [:active, :rejected])
    system.add(active: [:suspended, :deactivated])
    system.add(suspended: [:active, :deactivated])
    system.add(deactivated: [:active])
    system.add(:rejected)
    system.lock

    machine = StateJacket::StateMachine.new(system, state: @user.status)
    machine.on :activate, pending: :active
    machine.on :reject, pending: :rejected
    machine.on :suspend, active: :suspended
    machine.on :reactivate, [:suspended, :deactivated] => :active
    machine.on :deactivate, [:active, :suspended] => :deactivated
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
  in { state: "pending", actions: events } if events.include?("approve")
    render_approval_form
  in { state: "approved", destinations: ["completed"] }
    render_completion_button
  in { terminal?: true }
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
  in { success?: true, from: "pending", to: "approved", event: "approve" }
    send_approval_notification
    update_inventory_status
  in { success?: true, from: "pending", to: "rejected", event: "reject" }
    send_rejection_notification
    log_rejection_reason
  in { failed?: true, from: "pending", event: event_name }
    handle_transition_failure(event_name)
  end
end
```

### Pattern Matching with Guard Clauses

Combine patterns with business logic:

```ruby
def determine_user_permissions(machine)
  case machine
  in { state: "pending", actions: events } if events.include?("activate")
    [:view_profile, :complete_verification]
  in { state: "active", reachable_states: states } if states.include?("premium")
    [:read, :write, :comment, :upgrade_to_premium]
  in { state: "premium", terminal?: false }
    [:read, :write, :comment, :moderate, :export_data]
  in { terminal?: true }
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

**StateJacket:**

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
    in { success?: true }
      success("Payment processed")
    in { failed?: true }
      failure("Payment failed")
    end
  end

  def cancel!
    result = @machine.trigger(:cancel) do |from, to|
      self.state = to
      notify_cancellation
    end

    case result
    in { success?: true }
      success("Order cancelled")
    in { failed?: true }
      failure("Cannot cancel order")
    end
  end

  def state
    @machine.state
  end

  private

  def build_state_machine
    system = StateJacket::StateTransitionSystem.new
    system.add(pending: [:paid, :cancelled])
    system.add(:paid, :cancelled)
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

### From StateMachines gem

<details>
<summary><strong>StateMachines Migration</strong> - Converting from state_machines</summary>

**StateMachines:**

```ruby
class Vehicle
  state_machine :state, initial: :parked do
    event :ignite do
      transition parked: :idling
    end

    event :shift_up do
      transition idling: :first_gear, first_gear: :second_gear
    end

    before_transition any => :idling do |vehicle|
      vehicle.start_engine
    end
  end
end
```

**StateJacket:**

```ruby
class Vehicle
  def initialize
    @machine = build_state_machine
  end

  def ignite!
    result = @machine.trigger(:ignite) do |from, to|
      start_engine
      self.state = to
    end

    case result
    in { success?: true }
      { success: true, message: "Engine started" }
    in { failed?: true }
      { success: false, error: "Cannot start engine" }
    end
  end

  def shift_up!
    result = @machine.trigger(:shift_up) do |from, to|
      self.state = to
      adjust_gear(to)
    end

    case result
    in { success?: true, to: gear }
      { success: true, message: "Shifted to #{gear}" }
    in { failed?: true }
      { success: false, error: "Cannot shift up" }
    end
  end

  def state
    @machine.state
  end

  private

  def build_state_machine
    system = StateJacket::StateTransitionSystem.new
    system.add(parked: [:idling])
    system.add(idling: [:first_gear, :parked])
    system.add(first_gear: [:second_gear, :idling])
    system.add(second_gear: [:first_gear])
    system.lock

    machine = StateJacket::StateMachine.new(system, state: :parked)
    machine.on :ignite, parked: :idling
    machine.on :shift_up, {idling: :first_gear, first_gear: :second_gear}
    machine.on :shift_down, {second_gear: :first_gear, first_gear: :idling}
    machine.on :park, [:idling, :first_gear] => :parked
    machine.lock
    machine
  end

  def start_engine
    # Engine starting logic
  end

  def adjust_gear(gear)
    # Gear adjustment logic
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
      machine.can_trigger?(:approve)  # Safe concurrent reads
      machine.state                   # Safe concurrent reads
    end
  end
end
threads.each(&:join)
```

### Complex State Hierarchies

Handle complex workflows with multiple paths:

```ruby
system = StateJacket::StateTransitionSystem.new
system.add(idle: [:connecting, :error])
system.add(connecting: [:connected, :failed, :timeout, :error])
system.add(connected: [:idle, :transferring])
system.add(transferring: [:connected, :completed, :error])
system.add(:completed, :failed, :timeout, :error)
system.lock

machine = StateJacket::StateMachine.new(system, state: :idle)
machine.on :connect, idle: :connecting
machine.on :success, connecting: :connected
machine.on :fail, connecting: :failed
machine.on :timeout_event, connecting: :timeout
machine.on :transfer, connected: :transferring
machine.on :complete, transferring: :completed
machine.on :disconnect, {connected: :idle, transferring: :connected}
machine.on :error_out, {idle: :error, connecting: :error, transferring: :error}
machine.lock
```

### State Machine Introspection

Rich introspection capabilities for debugging and UI generation:

```ruby
# Current state information
machine.state                    # => "pending"
machine.state_symbol             # => :pending
machine.terminal?                # => false

# Available actions
machine.triggerable_events       # => ["approve", "reject"]
machine.reachable_states         # => ["approved", "rejected"]
machine.can_trigger?(:approve)   # => true

# All events and states
machine.events                   # => ["approve", "reject", "cancel"]
machine.states                   # => ["pending", "approved", "rejected"]

# Transition system information
system.transitioners             # => ["pending"]
system.terminators               # => ["approved", "rejected"]
system.can_transition?(pending: [:approved, :rejected])  # => true
```

## Performance & Production

### Performance Characteristics

StateJacket delivers exceptional performance through intelligent design:

- **1.7M+ transitions/second** - State machine mechanics are never your bottleneck
- **O(1) transition lookups** - Performance stays consistent as complexity grows
- **Memory efficient** - Frozen data structures with pre-computed caches
- **Thread-safe** - No synchronization overhead after locking

### Real-World Performance Impact

```ruby
# StateJacket's speed matters in high-frequency scenarios
def handle_websocket_message(message)
  case connection_machine.trigger(:receive_message)  # ← Microseconds
  in { success?: true, to: "authenticated" }
    process_authenticated_message(message)           # ← Your bottleneck
  in { success?: true, to: "rate_limited" }
    drop_message_silently
  end
end

# Batch processing benefits from consistent performance
invoices.each do |invoice|
  case invoice_machine.trigger(:process)  # ← Fast, consistent
  in { success?: true }
    update_database(invoice)              # ← Your bottleneck
  end
end
```

**Important:** Real applications are bottlenecked by database calls, API requests, and business logic. StateJacket ensures the state machine itself never becomes a performance concern.

### Production Considerations

<details>
<summary><strong>Monitoring & Observability</strong></summary>

```ruby
class InstrumentedStateMachine
  def initialize(machine, logger: Rails.logger)
    @machine = machine
    @logger = logger
  end

  def trigger(event)
    start_time = Time.current

    result = @machine.trigger(event) do |from, to|
      @logger.info "State transition: #{from} -> #{to} via #{event}"
      yield from, to if block_given?
    end

    duration = Time.current - start_time
    @logger.info "Transition completed in #{duration}ms"

    case result
    in { success?: true, from:, to: }
      Metrics.increment('state_machine.transition.success',
                       tags: { from: from, to: to, event: event })
    in { failed?: true }
      Metrics.increment('state_machine.transition.failure',
                       tags: { state: @machine.state, event: event })
    end

    result
  end

  def method_missing(method, *args, &block)
    @machine.send(method, *args, &block)
  end
end
```

</details>

<details>
<summary><strong>Error Handling Best Practices</strong></summary>

```ruby
class RobustOrderProcessor
  def process_payment!
    result = @machine.trigger(:pay) do |from, to|
      PaymentService.charge(payment_method, amount)
    rescue PaymentService::InsufficientFunds => e
      raise TransitionError.new("Insufficient funds: #{e.message}")
    rescue PaymentService::NetworkError => e
      raise TransitionError.new("Payment service unavailable: #{e.message}")
    end

    case result
    in { success?: true }
      success("Payment processed")
    in { failed?: true }
      # State wasn't changed due to exception
      failure("Payment failed - please try again")
    end
  rescue TransitionError => e
    # Handle transition-specific errors
    failure(e.message)
  rescue => e
    # Handle unexpected errors
    logger.error "Unexpected error in payment processing: #{e.message}"
    failure("An unexpected error occurred")
  end
end
```

</details>

## Testing

### Testing State Transition Systems

Test business rules independently:

```ruby
RSpec.describe "Order state transitions" do
  let(:system) do
    StateJacket::StateTransitionSystem.new.tap do |s|
      s.add(pending: [:processing, :cancelled])
      s.add(processing: [:completed, :failed])
      s.add(:completed, :cancelled, :failed)
      s.lock
    end
  end

  it "defines all expected states" do
    expect(system.states).to contain_exactly("pending", "processing", "completed", "cancelled", "failed")
  end

  it "validates legal transitions" do
    expect(system.can_transition?(pending: :processing)).to be true
    expect(system.can_transition?(processing: :completed)).to be true
  end

  it "rejects illegal transitions" do
    expect(system.can_transition?(completed: :pending)).to be false
  end
end
```

### Testing State Machines

Test event logic separately:

```ruby
RSpec.describe "Order state machine" do
  let(:system) { build_order_transition_system }
  let(:machine) do
    StateJacket::StateMachine.new(system, state: :pending).tap do |m|
      m.on :process, pending: :processing
      m.on :complete, processing: :completed
      m.on :cancel, pending: :cancelled
      m.lock
    end
  end

  it "transitions on valid events" do
    result = machine.trigger(:process)
    expect(result).to be_success
    expect(machine.state).to eq("processing")
  end

  it "returns failure for invalid transitions" do
    result = machine.trigger(:complete)  # Can't complete from pending
    expect(result).to be_failed
    expect(machine.state).to eq("pending")
  end
end
```

### Testing Business Logic

Test validation and callbacks independently:

```ruby
RSpec.describe OrderProcessor do
  let(:order) { build(:order, :with_items) }
  let(:processor) { OrderProcessor.new(order) }

  describe "#process_payment!" do
    context "with valid payment method" do
      let(:payment_method) { build(:payment_method, :valid) }

      it "processes payment successfully" do
        result = processor.process_payment!(payment_method)
        expect(result[:success]).to be true
        expect(processor.state).to eq("paid")
      end
    end

    context "with invalid payment method" do
      let(:payment_method) { build(:payment_method, :invalid) }

      it "fails with validation error" do
        result = processor.process_payment!(payment_method)
        expect(result[:success]).to be false
        expect(result[:error]).to include("Invalid payment method")
        expect(processor.state).to eq("pending")
      end
    end
  end
end
```

### Pattern Matching in Tests

Use pattern matching for cleaner test assertions:

```ruby
RSpec.describe "Order workflow" do
  it "processes orders successfully" do
    result = processor.checkout!

    case result
    in { success: true, message: String => msg }
      expect(msg).to include("submitted")
    else
      fail "Expected successful checkout"
    end
  end

  it "handles validation failures gracefully" do
    allow(processor).to receive(:valid_address?).and_return(false)

    result = processor.checkout!

    case result
    in { success: false, error: String => error }
      expect(error).to include("address")
    else
      fail "Expected validation error"
    end
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

### Running Tests

```bash
# Run all tests
bundle exec rake test

# Run specific test file
bundle exec ruby test/state_machine_test.rb

# Run performance benchmarks
bundle exec ruby bin/benchmark
```

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).

---

**StateJacket** - State machines that don't get in your way.
