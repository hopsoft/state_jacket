# frozen_string_literal: true

module StateJacket
  class StateTransitionSystem
    # @rbs @transitions: Hash[String, Array[String]?]
    # @rbs @locked: bool?

    # @rbs return: void
    def initialize
      @transitions = {}
    end

    # Returns a duplicate of the internal transitions hash
    # @rbs return: Hash[String, Array[String]?]
    def to_h
      transitions.dup
    end

    # Adds a state or state transition to the system
    # @rbs state: (String | Symbol | BasicObject | Hash[String | Symbol | BasicObject, (String | Symbol | BasicObject | Array[String | Symbol | BasicObject])]) -- State or transition definition (any object that responds to to_s, or Hash with keys/values that respond to to_s)
    # @rbs return: Array[String]?
    def add(state)
      raise "states cannot be added after locking" if is_locked?
      if state.is_a?(Hash)
        from = state.keys.first.to_s
        transitions[from] = make_states(state.values.first)
      else
        transitions[state.to_s] = nil
      end
    end

    # Locks the transition system to prevent further modifications
    # @rbs return: bool
    def lock
      return true if is_locked?
      transitions.freeze
      transitions.values.each { |value| value&.freeze }
      @locked = true
    end

    # Checks if the transition system is locked
    # @rbs return: bool
    def is_locked?
      !!@locked
    end

    # Checks if a transition is allowed in the system
    # @rbs from_to: Hash[String | Symbol | BasicObject, (String | Symbol | BasicObject | Array[String | Symbol | BasicObject])] -- Hash containing from => to transition (keys/values respond to to_s)
    # @rbs return: bool
    def can_transition?(from_to)
      raise ArgumentError.new("from_to should contain a single transition") unless from_to.size == 1
      from = from_to.keys.first.to_s
      to = make_states(from_to.values.first)
      allowed_states = transitions[from] || []
      (to & allowed_states).length == to.length
    end

    # Returns all states in the system
    # @rbs return: Array[String]
    def states
      transitions.keys
    end

    # Returns states that can transition to other states
    # @rbs return: Array[String]
    def transitioners
      transitions.keys.select { |state| !transitions[state].nil? }
    end

    # Returns terminal states (states with no outgoing transitions)
    # @rbs return: Array[String]
    def terminators
      transitions.keys.select { |state| transitions[state].nil? }
    end

    # Checks if a given value is a valid state in the system
    # @rbs state: String | Symbol | BasicObject -- State to check (any object that responds to to_s)
    # @rbs return: bool
    def is_state?(state)
      transitions.key? state.to_s
    end

    # Checks if a state is a terminator (has no outgoing transitions)
    # @rbs state: String | Symbol | BasicObject -- State to check (any object that responds to to_s)
    # @rbs return: bool
    def is_terminator?(state)
      terminators.include?(state.to_s)
    end

    # Checks if a state can transition to other states
    # @rbs state: String | Symbol | BasicObject -- State to check (any object that responds to to_s)
    # @rbs return: bool
    def is_transitioner?(state)
      transitioners.include?(state.to_s)
    end

    private

    attr_reader :transitions #: Hash[String, Array[String]?] # standard:disable Layout/LeadingCommentSpace

    # Normalizes input values into an array of string states
    # @rbs values: (String | Symbol | BasicObject | Array[String | Symbol | BasicObject]) -- Values to normalize into states (any object or array of objects that respond to to_s)
    # @rbs return: Array[String]
    def make_states(values)
      values = [values.to_s] unless values.respond_to?(:map)
      values = values.map(&:to_s)
      values.each { |value| transitions[value] ||= nil } unless transitions.frozen?
      values
    end
  end
end
