require "pry-test"
require "coveralls"
Coveralls.wear!
SimpleCov.command_name "pry-test"
require_relative "../lib/state_jacket/catalog"

class CatalogTest < PryTest::Test
  before do
    @catalog = StateJacket::Catalog.new
  end

  test "add state" do
    @catalog.add :start
    assert @catalog.has_key?("start")
  end

  test "terminators" do
    @catalog.add :start => [:finish]
    @catalog.add :finish
    @catalog.lock
    assert @catalog.terminators == ["finish"]
  end

  test "terminator" do
    @catalog.add :start => [:finish]
    @catalog.add :finish
    @catalog.lock
    assert @catalog.terminator?(:finish)
  end

  test "transitioners" do
    @catalog.add :start => [:finish]
    @catalog.add :finish
    @catalog.lock
    assert @catalog.transitioners == ["start"]
  end

  test "transitioner" do
    @catalog.add :start => [:finish]
    @catalog.add :finish
    @catalog.lock
    assert @catalog.transitioner?(:start)
  end

  test "can transition" do
    @catalog.add :start => [:finish]
    @catalog.add :finish
    @catalog.lock
    assert @catalog.can_transition?(:start => :finish)
  end

  test "supports state" do
    @catalog.add :start => [:finish]
    @catalog.add :finish
    @catalog.lock
    assert @catalog.supports_state?(:start)
    assert @catalog.supports_state?(:finish)
  end

  test "lock failure" do
    @catalog.add :start => [:finish]
    begin
      @catalog.lock
    rescue Exception => e
    end
    assert e.message.start_with?("Invalid StateJacket::Catalog!")
  end

  test "lock success" do
    @catalog.add :start => [:finish]
    @catalog.add :finish
    begin
      @catalog.lock
    rescue Exception => e
    end
    assert e.nil?
  end

  test "symbol state" do
    @catalog.add :start => [:finish]
    @catalog.add :finish
    assert @catalog.keys.include?("start")
    assert @catalog.can_transition?(:start => :finish)
  end

  test "string state" do
    @catalog.add "start" => ["finish"]
    @catalog.add "finish"
    assert @catalog.keys.include?("start")
    assert @catalog.can_transition?("start" => "finish")
  end

  test "number state" do
    @catalog.add 1 => [2]
    @catalog.add 2
    assert @catalog.keys.include?("1")
    assert @catalog.can_transition?(1 => 2)
  end

  test "turnstyle example" do
    @catalog.add :open => [:closed, :error]
    @catalog.add :closed => [:open, :error]
    @catalog.add :error
    @catalog.lock
    assert @catalog.transitioners == ["open", "closed"]
    assert @catalog.terminators == ["error"]
    assert @catalog.can_transition?(:open => :closed)
    assert @catalog.can_transition?(:closed => :open)
    assert @catalog.can_transition?(:error => :open) == false
    assert @catalog.can_transition?(:error => :closed) == false
  end

  test "phone call example" do
    @catalog = StateJacket::Catalog.new
    @catalog.add :idle => [:dialing]
    @catalog.add :dialing => [:idle, :connecting]
    @catalog.add :connecting => [:idle, :busy, :connected]
    @catalog.add :busy => [:idle]
    @catalog.add :connected => [:idle]
    @catalog.lock
    assert @catalog.transitioners == ["idle", "dialing", "connecting", "busy", "connected"]
    assert @catalog.terminators == []
    assert @catalog.can_transition?(:idle => :dialing)
    assert @catalog.can_transition?(:dialing => [:idle, :connecting])
    assert @catalog.can_transition?(:connecting => [:idle, :busy, :connected])
    assert @catalog.can_transition?(:busy => :idle)
    assert @catalog.can_transition?(:connected => :idle)
    assert @catalog.can_transition?(:idle => [:dialing, :connected]) == false
  end

end
