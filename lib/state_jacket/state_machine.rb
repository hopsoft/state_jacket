# frozen_string_literal: true

module StateJacket
  class StateMachine
    # @rbs @transition_system: StateTransitionSystem
    # @rbs @state: String
    # @rbs @triggers: Hash[String, Array[Hash[String, String]]]
    # @rbs @locked: bool?
    attr_reader :state #: String # standard:disable Layout/LeadingCommentSpace

    # Initializes a new state machine with a transition system and initial state
    # @rbs transition_system: StateTransitionSystem -- The state transition system to use
    # @rbs state: String | Symbol | BasicObject -- The initial state (any object that responds to to_s)
    # @rbs return: void
    def initialize(transition_system, state:)
      transition_system.lock
      raise ArgumentError.new("illegal state") unless transition_system.is_state?(state)
      @transition_system = transition_system
      @state = state.to_s
      @triggers = {}
    end

    # Returns a duplicate of the internal triggers hash
    # @rbs return: Hash[String, Array[Hash[String, String]]]
    def to_h
      triggers.dup
    end

    # Returns all event names defined in the state machine
    # @rbs return: Array[String]
    def events
      triggers.keys
    end

    # Defines an event with its associated state transitions
    # @rbs event: String | Symbol | BasicObject -- The event name (any object that responds to to_s)
    # @rbs transitions: Hash[String | Symbol | BasicObject, String | Symbol | BasicObject] -- Hash of from_state => to_state transitions (keys/values respond to to_s)
    # @rbs return: void
    def on(event, transitions = {})
      raise "events cannot be added after locking" if is_locked?
      raise ArgumentError.new("event has already been added") if is_event?(event)
      transitions.each do |from, to|
        raise ArgumentError.new("illegal transition") unless transition_system.can_transition?(from => to)
        triggers[event.to_s] ||= []
        triggers[event.to_s] << {from.to_s => to.to_s}
        triggers[event.to_s].uniq!
      end
    end

    # Triggers an event to transition the state machine
    # @rbs event: String | Symbol | BasicObject -- The event to trigger (any object that responds to to_s)
    # @rbs &block: ? (String, String) -> void -- Optional block receiving from_state and to_state
    # @rbs return: String?
    def trigger(event)
      raise "must be locked before triggering events" unless is_locked?
      raise ArgumentError.new("event not defined") unless is_event?(event)
      transition = transition_for(event)
      return nil unless transition
      from = @state
      to = transition.values.first
      raise "current state doesn't match transition state" unless from == transition.keys.first
      yield from, to if block_given?
      @state = to
      to
    end

    # Locks the state machine to prevent further event definitions
    # @rbs return: bool
    def lock
      return true if is_locked?
      triggers.freeze
      triggers.values.map(&:freeze)
      triggers.values.freeze
      @locked = true
    end

    # Checks if the state machine is locked
    # @rbs return: bool
    def is_locked?
      !!@locked
    end

    # Checks if an event is defined in the state machine
    # @rbs event: String | Symbol | BasicObject -- The event to check (any object that responds to to_s)
    # @rbs return: bool
    def is_event?(event)
      triggers.has_key? event.to_s
    end

    # Checks if an event can be triggered from the current state
    # @rbs event: String | Symbol | BasicObject -- The event to check (any object that responds to to_s)
    # @rbs return: bool
    def can_trigger?(event)
      return false unless is_locked?
      !!transition_for(event)
    end

    private

    attr_reader :transition_system #: StateTransitionSystem # standard:disable Layout/LeadingCommentSpace
    attr_reader :triggers #: Hash[String, Array[Hash[String, String]]] # standard:disable Layout/LeadingCommentSpace

    # Finds the transition for an event from the current state
    # @rbs event: String | Symbol | BasicObject -- The event to find transition for (any object that responds to to_s)
    # @rbs return: Hash[String, String]?
    def transition_for(event)
      triggers[event.to_s].find { |entry| entry.keys.first == state }
    end
  end
end
