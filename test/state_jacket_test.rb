require "pry-test"
require "coveralls"
Coveralls.wear!
SimpleCov.command_name "pry-test"
require_relative "../lib/state_jacket"

class StateJacketTest < PryTest::Test
  before do
    @jacket = StateJacket.new
  end

  test "add state" do
    @jacket.add :start
    assert @jacket.to_h.has_key?("start")
  end

  test "terminators" do
    @jacket.add start: [:finish]
    @jacket.add :finish
    @jacket.lock
    assert @jacket.terminators == ["finish"]
  end

  test "is_terminator?" do
    @jacket.add start: [:finish]
    @jacket.add :finish
    @jacket.lock
    assert @jacket.is_terminator?(:finish)
  end

  test "transitioners" do
    @jacket.add start: [:finish]
    @jacket.add :finish
    @jacket.lock
    assert @jacket.transitioners == ["start"]
  end

  test "is_transitioner?" do
    @jacket.add start: [:finish]
    @jacket.add :finish
    @jacket.lock
    assert @jacket.is_transitioner?(:start)
  end

  test "can_transition?" do
    @jacket.add start: [:finish]
    @jacket.add :finish
    @jacket.lock
    assert @jacket.can_transition?(start: :finish)
  end

  test "is_state?" do
    @jacket.add start: [:finish]
    @jacket.add :finish
    @jacket.lock
    assert @jacket.is_state?(:start)
    assert @jacket.is_state?(:finish)
  end

  test "lock success" do
    @jacket.add start: [:finish]
    @jacket.add :finish
    begin
      @jacket.lock
    rescue Exception => e
    end
    assert e.nil?
  end

  test "symbol state" do
    @jacket.add start: [:finish]
    @jacket.add :finish
    assert @jacket.to_h.keys.include?("start")
    assert @jacket.can_transition?(start: :finish)
  end

  test "string state" do
    @jacket.add "start" => ["finish"]
    @jacket.add "finish"
    assert @jacket.to_h.keys.include?("start")
    assert @jacket.can_transition?("start" => "finish")
  end

  test "number state" do
    @jacket.add 1 => [2]
    @jacket.add 2
    assert @jacket.to_h.keys.include?("1")
    assert @jacket.can_transition?(1 => 2)
  end

  test "turnstyle example" do
    @jacket.add open: [:closed, :error]
    @jacket.add closed: [:open, :error]
    @jacket.add :error
    @jacket.lock
    assert @jacket.transitioners.sort == ["closed", "open"]
    assert @jacket.terminators == ["error"]
    assert @jacket.can_transition?(open: :closed)
    assert @jacket.can_transition?(closed: :open)
    assert @jacket.can_transition?(error: :open) == false
    assert @jacket.can_transition?(error: :closed) == false
  end

  test "phone call example" do
    @jacket = StateJacket.new
    @jacket.add idle: [:dialing]
    @jacket.add dialing: [:idle, :connecting]
    @jacket.add connecting: [:idle, :busy, :connected]
    @jacket.add busy: [:idle]
    @jacket.add connected: [:idle]
    @jacket.lock
    assert @jacket.transitioners.sort == ["busy", "connected", "connecting", "dialing", "idle"]
    assert @jacket.terminators == []
    assert @jacket.can_transition?(idle: :dialing)
    assert @jacket.can_transition?(dialing: [:idle, :connecting])
    assert @jacket.can_transition?(connecting: [:idle, :busy, :connected])
    assert @jacket.can_transition?(busy: :idle)
    assert @jacket.can_transition?(connected: :idle)
    assert @jacket.can_transition?(idle: [:dialing, :connected]) == false
  end
end
