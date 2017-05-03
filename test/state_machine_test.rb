require_relative "./test_helper"

class StateMachineTest < PryTest::Test
  before do
    @transitions = StateJacket::TransitionSystem.new
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

  test "new locks the jacket" do
    @transitions.add opened: [:closed, :errored]
    @transitions.add closed: [:opened, :errored]
    StateJacket::StateMachine.new(@transitions, state: :closed)
    assert @transitions.locked?
  end

  test "creating an event that has an illegal transition fails" do
    @transitions.add opened: [:closed, :errored]
    @transitions.add closed: [:opened, :errored]
    machine = StateJacket::StateMachine.new(@transitions, state: :closed)
    begin
      machine.on :open, closed: :fubar
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
    assert machine.to_h == {
      "transitions" => {
        "closed" => ["opened", "errored"],
        "errored" => nil,
        "opened" => ["closed", "errored"]
      },
      "events" => {
        "open" => [{"closed" => "opened"}],
        "close" => [{"opened" => "closed"}]
      }
    }
  end

  test "lock prevents future mutations" do
    @transitions.add opened: [:closed, :errored]
    @transitions.add closed: [:opened, :errored]
    machine = StateJacket::StateMachine.new(@transitions, state: :closed)
    machine.on :open, closed: :opened
    machine.on :close, opened: :closed
    assert machine.lock
    assert machine.locked?
    begin
      machine.on :error, closed: :opened
    rescue ArgumentError => e
    end
    assert e
  end

  test "trigger event sets matching state" do
    @transitions.add opened: [:closed]
    @transitions.add closed: [:opened]
    machine = StateJacket::StateMachine.new(@transitions, state: :closed)
    machine.on :open, closed: :opened
    machine.on :close, opened: :closed
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
    machine.trigger(:open) { "consumer logic goes here..." }
    assert machine.state == "opened"
    machine.trigger(:close) { "consumer logic goes here..." }
    assert machine.state == "closed"
  end

  test "trigger event does not set state if error in block" do
    @transitions.add opened: [:closed]
    @transitions.add closed: [:opened]
    machine = StateJacket::StateMachine.new(@transitions, state: :closed)
    machine.on :open, closed: :opened
    machine.on :close, opened: :closed
    machine.trigger(:open) { raise } rescue nil
    assert machine.state == "closed"
  end
end
