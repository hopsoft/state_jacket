require_relative "./test_helper"

class StateMachineTest < PryTest::Test
  before do
    @transitions = StateJacket::StateTransitionSystem.new
  end

  test "new raises with invalid state" do
    @transitions.add opened: [:closed, :errored]
    @transitions.add closed: [:opened, :errored]
    begin
      StateJacket::StateMachine.new(@transitions, state: :foo)
    rescue ArgumentError => e
    end
    assert e
  end

  test "new assigns state" do
    @transitions.add opened: [:closed, :errored]
    @transitions.add closed: [:opened, :errored]
    machine = StateJacket::StateMachine.new(@transitions, state: :opened)
    assert machine.state == "opened"
  end

  test "new locks the jacket" do
    @transitions.add opened: [:closed, :errored]
    @transitions.add closed: [:opened, :errored]
    StateJacket::StateMachine.new(@transitions, state: :closed)
    assert @transitions.is_locked?
  end

  test "creating an event that has an illegal transition fails" do
    @transitions.add opened: [:closed, :errored]
    @transitions.add closed: [:opened, :errored]
    machine = StateJacket::StateMachine.new(@transitions, state: :closed)
    begin
      machine.on :reopen, errored: :open
    rescue StandardError => e
    end
    assert e
  end

  test "to_h" do
    @transitions.add opened: [:closed, :errored]
    @transitions.add closed: [:opened, :errored]
    machine = StateJacket::StateMachine.new(@transitions, state: :closed)
    machine.on :open, closed: :opened
    machine.on :close, opened: :closed
    assert machine.to_h == {"open"=>[{"closed"=>"opened"}], "close"=>[{"opened"=>"closed"}]}
  end

  test "lock prevents future mutations" do
    @transitions.add opened: [:closed, :errored]
    @transitions.add closed: [:opened, :errored]
    machine = StateJacket::StateMachine.new(@transitions, state: :closed)
    machine.on :open, closed: :opened
    machine.on :close, opened: :closed
    assert machine.lock
    assert machine.is_locked?
    begin
      machine.on :error, closed: :opened
    rescue StandardError => e
    end
    assert e
  end

  test "can't trigger events unless locked" do
    @transitions.add opened: [:closed]
    @transitions.add closed: [:opened]
    machine = StateJacket::StateMachine.new(@transitions, state: :closed)
    machine.on :open, closed: :opened
    machine.on :close, opened: :closed
    begin
      machine.trigger :open
    rescue StandardError => e
    end
    assert e
  end

  test "trigger event sets matching state" do
    @transitions.add opened: [:closed]
    @transitions.add closed: [:opened]
    machine = StateJacket::StateMachine.new(@transitions, state: :closed)
    machine.on :open, closed: :opened
    machine.on :close, opened: :closed
    machine.lock
    machine.trigger :open
    assert machine.state == "opened"
    machine.trigger :close
    assert machine.state == "closed"
  end

  test "trigger event sets matching state with block" do
    @transitions.add opened: [:closed]
    @transitions.add closed: [:opened]
    machine = StateJacket::StateMachine.new(@transitions, state: :closed)
    machine.on :open, closed: :opened
    machine.on :close, opened: :closed
    machine.lock
    machine.trigger(:open) { |from, to| "consumer logic goes here..." }
    assert machine.state == "opened"
    machine.trigger(:close) { |from, to| "consumer logic goes here..." }
    assert machine.state == "closed"
  end

  test "trigger event does not set state if error in block" do
    @transitions.add opened: [:closed]
    @transitions.add closed: [:opened]
    machine = StateJacket::StateMachine.new(@transitions, state: :closed)
    machine.on :open, closed: :opened
    machine.on :close, opened: :closed
    machine.lock
    machine.trigger(:open) { |from, to| raise } rescue nil
    assert machine.state == "closed"
  end

  test "trigger event passes from/to states to block" do
    @transitions.add opened: [:closed]
    @transitions.add closed: [:opened]
    machine = StateJacket::StateMachine.new(@transitions, state: :closed)
    machine.on :open, closed: :opened
    machine.on :close, opened: :closed
    machine.lock
    states = { from: nil, to: nil }
    machine.trigger :open do |from, to|
      states[:from] = from
      states[:to] = to
    end
    assert states == { from: "closed", to: "opened" }
  end

  test "can_trigger? false unless locked" do
    @transitions.add opened: [:closed, :errored]
    @transitions.add closed: [:opened, :errored]
    machine = StateJacket::StateMachine.new(@transitions, state: :closed)
    machine.on :open, closed: :opened
    machine.on :close, opened: :closed
    assert !machine.can_trigger?(:open)
  end

  test "can_trigger?" do
    @transitions.add opened: [:closed, :errored]
    @transitions.add closed: [:opened, :errored]
    machine = StateJacket::StateMachine.new(@transitions, state: :closed)
    machine.on :open, closed: :opened
    machine.on :close, opened: :closed
    machine.lock
    assert machine.can_trigger?(:open)
  end

  test "can_trigger? false" do
    @transitions.add opened: [:closed, :errored]
    @transitions.add closed: [:opened, :errored]
    machine = StateJacket::StateMachine.new(@transitions, state: :closed)
    machine.on :open, closed: :opened
    machine.on :close, opened: :closed
    machine.lock
    assert !machine.can_trigger?(:close)
  end
end
