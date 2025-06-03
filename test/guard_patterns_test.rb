# frozen_string_literal: true

require_relative "test_helper"

# Tests demonstrating the explicit validation patterns documented in the README.
#
# StateJacket intentionally omits built-in guards to maintain simplicity and
# promote separation of concerns. These tests illustrate the recommended patterns
# for handling business logic validation:
#
# 1. Explicit Validation Methods - Check conditions before triggering transitions
# 2. Validator Objects - Extract complex validation into dedicated classes
# 3. Command Objects - Encapsulate validation and execution logic together
#
# These patterns demonstrate that explicit validation is often superior to
# built-in guards because it's more testable, flexible, and maintainable.
class GuardPatternsTest < Minitest::Test
  def test_explicit_validation_methods_pattern
    processor = PaymentProcessor.new(100, Account.new(balance: 50))

    # Should fail validation before triggering state transition
    result = processor.process!
    assert_equal "Insufficient funds", result[:error]
    assert_equal "failed", processor.state

    # Should succeed with sufficient funds
    processor = PaymentProcessor.new(50, Account.new(balance: 100))
    result = processor.process!
    assert result[:success]
    assert_equal "processing", processor.state
  end

  def test_explicit_validation_methods_with_multiple_checks
    # Test invalid payment method
    account = Account.new(balance: 100, payment_method: InvalidPaymentMethod.new)
    processor = PaymentProcessor.new(50, account)

    result = processor.process!
    assert_equal "Invalid payment", result[:error]
    assert_equal "failed", processor.state

    # Test valid scenario
    account = Account.new(balance: 100, payment_method: ValidPaymentMethod.new)
    processor = PaymentProcessor.new(50, account)

    result = processor.process!
    assert result[:success]
    assert_equal "processing", processor.state
  end

  def test_validator_objects_pattern
    # Test with invalid order
    empty_order = Order.new(items: [])
    workflow = OrderWorkflow.new(empty_order)

    result = workflow.checkout!
    refute result.valid?
    assert_includes result.errors, "Cart is empty"
    assert_equal "cart", workflow.state

    # Test with invalid address
    order_with_invalid_address = Order.new(
      items: [Item.new],
      shipping_address: InvalidAddress.new
    )
    workflow = OrderWorkflow.new(order_with_invalid_address)

    result = workflow.checkout!
    refute result.valid?
    assert_includes result.errors, "Invalid address"

    # Test valid order
    valid_order = Order.new(
      items: [Item.new],
      shipping_address: ValidAddress.new
    )
    workflow = OrderWorkflow.new(valid_order)

    result = workflow.checkout!
    assert result.valid?
    assert_equal "processing", workflow.state
  end

  def test_command_objects_pattern
    # Test document that fails validation
    unreviewed_document = Document.new(
      content: "Some content",
      reviewed: false,
      approved: true
    )

    command = PublishDocument.new(unreviewed_document)
    result = command.call

    assert_includes result, "Document must be reviewed"
    assert_equal "draft", unreviewed_document.state

    # Test document that passes validation
    valid_document = Document.new(
      content: "Great content",
      reviewed: true,
      approved: true
    )

    command = PublishDocument.new(valid_document)
    result = command.call

    assert result[:success]
    assert_equal "published", valid_document.state
    assert valid_document.published_at
    assert valid_document.subscribers_notified
  end

  def test_complex_validation_scenarios
    # Test that complex business logic works with explicit validation
    processor = ComplexPaymentProcessor.new(1500, VipCustomer.new)

    # VIP customer should be able to process large amounts
    result = processor.process_large_payment!
    assert result[:success]

    # Regular customer should not
    processor = ComplexPaymentProcessor.new(1500, RegularCustomer.new)
    result = processor.process_large_payment!
    assert_equal "Large payments require VIP status", result[:error]
  end

  def test_time_based_validation
    # Mock business hours check
    processor = BusinessHoursProcessor.new

    # Should fail outside business hours
    processor.stub(:during_business_hours?, false) do
      result = processor.process_during_hours!
      assert_equal "Processing only available during business hours", result[:error]
    end

    # Should succeed during business hours
    processor.stub(:during_business_hours?, true) do
      result = processor.process_during_hours!
      assert result[:success]
    end
  end

  def test_validation_independence_from_state_machine
    # Test that business logic can be tested independently
    account = Account.new(balance: 30)
    processor = PaymentProcessor.new(50, account)

    # Test business logic directly without state machine
    refute processor.send(:sufficient_funds?)

    account = Account.new(balance: 100)
    processor = PaymentProcessor.new(50, account)

    assert processor.send(:sufficient_funds?)
  end
end

# Supporting classes for the tests

class PaymentProcessor
  def initialize(amount, account)
    @amount = amount
    @account = account

    @transitions = StateJacket::StateTransitionSystem.new
    @transitions.add pending: [:processing, :failed]
    @transitions.add processing: [:completed, :failed]

    @machine = StateJacket::StateMachine.new(@transitions, state: :pending)
    @machine.on :process, pending: :processing
    @machine.on :complete, processing: :completed
    @machine.on :fail, {pending: :failed, processing: :failed}
    @machine.lock
  end

  def process!
    return failure("Insufficient funds") unless sufficient_funds?
    return failure("Invalid payment") unless valid_payment_method?

    @machine.trigger(:process) do |from, to|
      charge_payment
      send_receipt
    end

    {success: true}
  end

  def state
    @machine.state
  end

  private

  def sufficient_funds?
    @account.balance >= @amount
  end

  def valid_payment_method?
    @account.payment_method&.valid?
  end

  def charge_payment
    @account.balance -= @amount
  end

  def send_receipt
    # Mock receipt sending
  end

  def failure(message)
    @machine.trigger(:fail)
    {success: false, error: message}
  end
end

class OrderWorkflow
  def initialize(order)
    @order = order
    @machine = build_state_machine
  end

  def checkout!
    result = OrderValidator.new(@order).validate
    return result unless result.valid?

    @machine.trigger(:checkout)
    result
  end

  def state
    @machine.state
  end

  private

  def build_state_machine
    transitions = StateJacket::StateTransitionSystem.new
    transitions.add cart: [:processing, :failed]
    transitions.add processing: [:completed, :failed]

    machine = StateJacket::StateMachine.new(transitions, state: :cart)
    machine.on :checkout, cart: :processing
    machine.on :complete, processing: :completed
    machine.on :fail, {cart: :failed, processing: :failed}
    machine.lock
    machine
  end
end

class OrderValidator
  def initialize(order)
    @order = order
  end

  def validate
    errors = []
    errors << "Cart is empty" if @order.items.empty?
    errors << "Invalid address" unless @order.shipping_address&.valid?

    ValidationResult.new(errors)
  end
end

class ValidationResult
  attr_reader :errors

  def initialize(errors = [])
    @errors = errors
  end

  def valid?
    @errors.empty?
  end
end

class PublishDocument
  def initialize(document)
    @document = document
    @machine = build_state_machine
  end

  def call
    return validation_errors unless valid?

    @machine.trigger(:publish) do |from, to|
      @document.update_published_date
      notify_subscribers
    end

    {success: true}
  end

  private

  def valid?
    StringExtensions.present?(@document.content) &&
      @document.reviewed? &&
      @document.approved?
  end

  def validation_errors
    errors = []
    errors << "Content cannot be blank" if StringExtensions.blank?(@document.content)
    errors << "Document must be reviewed" unless @document.reviewed?
    errors << "Author approval required" unless @document.approved?
    errors
  end

  def notify_subscribers
    @document.subscribers_notified = true
  end

  def build_state_machine
    transitions = StateJacket::StateTransitionSystem.new
    transitions.add draft: [:published]

    machine = StateJacket::StateMachine.new(transitions, state: :draft)
    machine.on :publish, draft: :published
    machine.lock
    machine
  end
end

class ComplexPaymentProcessor
  def initialize(amount, customer)
    @amount = amount
    @customer = customer

    @transitions = StateJacket::StateTransitionSystem.new
    @transitions.add pending: [:processing, :failed]

    @machine = StateJacket::StateMachine.new(@transitions, state: :pending)
    @machine.on :process, pending: :processing
    @machine.on :fail, pending: :failed
    @machine.lock
  end

  def process_large_payment!
    return failure("Large payments require VIP status") unless can_process_large_payment?

    @machine.trigger(:process)
    {success: true}
  end

  private

  def can_process_large_payment?
    return true unless @amount > 1000
    @customer.vip?
  end

  def failure(message)
    @machine.trigger(:fail)
    {success: false, error: message}
  end
end

class BusinessHoursProcessor
  def initialize
    @transitions = StateJacket::StateTransitionSystem.new
    @transitions.add idle: [:processing, :failed]

    @machine = StateJacket::StateMachine.new(@transitions, state: :idle)
    @machine.on :process, idle: :processing
    @machine.on :fail, idle: :failed
    @machine.lock
  end

  def process_during_hours!
    unless during_business_hours?
      return failure("Processing only available during business hours")
    end

    @machine.trigger(:process)
    {success: true}
  end

  private

  def during_business_hours?
    # This would normally check actual time
    Time.now.hour.between?(9, 17)
  end

  def failure(message)
    @machine.trigger(:fail)
    {success: false, error: message}
  end
end

# Supporting value objects

Account = Struct.new(:balance, :payment_method, keyword_init: true) do
  def initialize(**args)
    super
    self.payment_method ||= ValidPaymentMethod.new
  end
end

class ValidPaymentMethod
  def valid?
    true
  end
end

class InvalidPaymentMethod
  def valid?
    false
  end
end

Order = Struct.new(:items, :shipping_address, keyword_init: true) do
  def initialize(**args)
    super
    self.items ||= []
  end
end

Item = Struct.new(:name, keyword_init: true) do
  def initialize(**args)
    super
    self.name ||= "Test Item"
  end
end

class ValidAddress
  def valid?
    true
  end
end

class InvalidAddress
  def valid?
    false
  end
end

class StringExtensions
  def self.present?(str)
    str && !str.empty?
  end

  def self.blank?(str)
    !present?(str)
  end
end

Document = Struct.new(:content, :reviewed, :approved, :published_at, :subscribers_notified, keyword_init: true) do
  def initialize(**args)
    super
    self.reviewed ||= false
    self.approved ||= false
    self.subscribers_notified ||= false
  end

  def reviewed?
    reviewed
  end

  def approved?
    approved
  end

  def update_published_date
    self.published_at = Time.now
  end

  def state
    published_at ? "published" : "draft"
  end
end

class VipCustomer
  def vip?
    true
  end
end

class RegularCustomer
  def vip?
    false
  end
end
