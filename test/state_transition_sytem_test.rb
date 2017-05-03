require_relative "./test_helper"

class StateJacketTest < PryTest::Test
  before do
    @transitions = StateJacket::StateTransitionSystem.new
  end

  test "add state" do
    @transitions.add :started
    assert @transitions.to_h.has_key?("started")
  end

  test "terminators" do
    @transitions.add started: [:finished]
    @transitions.lock
    assert @transitions.terminators == ["finished"]
  end

  test "is_terminator?" do
    @transitions.add started: [:finished]
    @transitions.lock
    assert @transitions.is_terminator?(:finished)
  end

  test "transitioners" do
    @transitions.add started: [:finished]
    @transitions.lock
    assert @transitions.transitioners == ["started"]
  end

  test "is_transitioner?" do
    @transitions.add started: [:finished]
    @transitions.lock
    assert @transitions.is_transitioner?(:started)
  end

  test "can_transition?" do
    @transitions.add started: [:finished]
    @transitions.lock
    assert @transitions.can_transition?(started: :finished)
  end

  test "is_state?" do
    @transitions.add started: [:finished]
    @transitions.lock
    assert @transitions.is_state?(:started)
    assert @transitions.is_state?(:finished)
  end

  test "lock success" do
    @transitions.add started: [:finished]
    begin
      @transitions.lock
    rescue Exception => e
    end
    assert e.nil?
  end

  test "states" do
    @transitions.add started: [:finished]
    @transitions.lock
    assert @transitions.states == %w(finished started)
  end

  test "symbol state" do
    @transitions.add started: [:finished]
    assert @transitions.to_h.keys.include?("started")
    assert @transitions.can_transition?(started: :finished)
  end

  test "string state" do
    @transitions.add "started" => ["finished"]
    assert @transitions.to_h.keys.include?("started")
    assert @transitions.can_transition?("started" => "finished")
  end

  test "number state" do
    @transitions.add 1 => [2]
    assert @transitions.to_h.keys.include?("1")
    assert @transitions.can_transition?(1 => 2)
  end

  test "turnstyle example" do
    @transitions.add opened: [:closed, :errored]
    @transitions.add closed: [:opened, :errored]
    @transitions.lock
    assert @transitions.transitioners.sort == ["closed", "opened"]
    assert @transitions.terminators == ["errored"]
    assert @transitions.can_transition?(opened: :closed)
    assert @transitions.can_transition?(closed: :opened)
    assert @transitions.can_transition?(errored: :opened) == false
    assert @transitions.can_transition?(errored: :closeded) == false
  end

  test "phone call example" do
    @transitions = StateJacket::StateTransitionSystem.new
    @transitions.add idle: [:dialing]
    @transitions.add dialing: [:idle, :connecting]
    @transitions.add connecting: [:idle, :busy, :connected]
    @transitions.add busy: [:idle]
    @transitions.add connected: [:idle]
    @transitions.lock
    assert @transitions.transitioners.sort == ["busy", "connected", "connecting", "dialing", "idle"]
    assert @transitions.terminators == []
    assert @transitions.can_transition?(idle: :dialing)
    assert @transitions.can_transition?(dialing: [:idle, :connecting])
    assert @transitions.can_transition?(connecting: [:idle, :busy, :connected])
    assert @transitions.can_transition?(busy: :idle)
    assert @transitions.can_transition?(connected: :idle)
    assert @transitions.can_transition?(idle: [:dialing, :connected]) == false
  end

  test "to_h" do
    @transitions.add opened: [:closed, :errored]
    @transitions.add closed: [:opened, :errored]
    @transitions.lock
    assert @transitions.to_h == {
      "closed"  => ["opened", "errored"],
      "errored" => nil,
      "opened"  => ["closed", "errored"]
    }
  end
end
