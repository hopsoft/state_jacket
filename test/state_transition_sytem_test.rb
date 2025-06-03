# frozen_string_literal: true

require_relative "test_helper"

class StateJacketTest < Minitest::Test
  def setup
    @transitions = StateJacket::StateTransitionSystem.new
  end

  def test_add_state
    @transitions.add :started
    assert @transitions.to_h.has_key?("started")
  end

  def test_terminators
    @transitions.add started: [:finished]
    @transitions.lock
    assert @transitions.terminators == ["finished"]
  end

  def test_terminator
    @transitions.add started: [:finished]
    @transitions.lock
    assert @transitions.terminator?(:finished)
  end

  def test_transitioners
    @transitions.add started: [:finished]
    @transitions.lock
    assert @transitions.transitioners == ["started"]
  end

  def test_transitioner
    @transitions.add started: [:finished]
    @transitions.lock
    assert @transitions.transitioner?(:started)
  end

  def test_can_transition
    @transitions.add started: [:finished]
    @transitions.lock
    assert @transitions.can_transition?(started: :finished)
  end

  def test_state
    @transitions.add started: [:finished]
    @transitions.lock
    assert @transitions.state?(:started)
    assert @transitions.state?(:finished)
  end

  def test_lock_success
    @transitions.add started: [:finished]
    begin
      @transitions.lock
    rescue => e
    end
    assert e.nil?
  end

  def test_states
    @transitions.add started: [:finished]
    @transitions.lock
    assert @transitions.states == %w[finished started]
  end

  def test_symbol_state
    @transitions.add started: [:finished]
    assert @transitions.to_h.key?("started")
    assert @transitions.can_transition?(started: :finished)
  end

  def test_string_state
    @transitions.add "started" => ["finished"]
    assert @transitions.to_h.key?("started")
    assert @transitions.can_transition?("started" => "finished")
  end

  def test_number_state
    @transitions.add 1 => [2]
    assert @transitions.to_h.key?("1")
    assert @transitions.can_transition?(1 => 2)
  end

  def test_turnstyle_example
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

  def test_phone_call_example
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

  def test_to_h
    @transitions.add opened: [:closed, :errored]
    @transitions.add closed: [:opened, :errored]
    @transitions.lock
    assert @transitions.to_h == {
      "closed" => ["opened", "errored"],
      "errored" => nil,
      "opened" => ["closed", "errored"]
    }
  end
end
