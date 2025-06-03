# frozen_string_literal: true

module StateJacket
  class StateTransitionSystem
    # @rbs @transitions: Hash[String, Array[String]?] -- Internal mapping of state names to their allowed transitions
    # @rbs @locked: bool -- Whether the transition system is locked (prevents further modifications)

    # Initializes a new state transition system with an empty transitions hash
    #
    # The StateTransitionSystem is the foundation layer of StateJacket's two-layer architecture.
    # It defines the "rules" - what states exist and which transitions are valid between them.
    # This separation allows you to define business rules independently from event logic.
    #
    # States and transitions can be added until the system is locked
    # @rbs return: void
    def initialize
      @transitions = {}
    end

    # Returns a duplicate of the internal transitions hash for inspection
    # Keys are state names (String), values are either nil (terminal state) or Array of allowed target states
    # @rbs return: Hash[String, Array[String]?] -- Shallow copy of the transitions mapping
    def to_h
      @transitions.dup
    end

    # Adds a state or state transition to the system
    #
    # This method defines the foundational rules of your state machine:
    # - Single states: add(:terminal_state) creates states with no outgoing transitions
    # - Transitions: add(from_state: [:dest1, :dest2]) defines allowed state flows
    #
    # Examples:
    #   system.add(:completed)                      # Terminal state
    #   system.add(pending: [:approved, :rejected]) # State with transitions
    #   system.add(draft: :published)               # Single transition
    #
    # System must not be locked when adding states
    # @rbs state: (String | Symbol | BasicObject | Hash[String | Symbol | BasicObject, (String | Symbol | BasicObject | Array[String | Symbol | BasicObject])]) -- Single state (converted to String via to_s) or transition hash with from_state => to_state(s)
    # @rbs return: Array[String]? -- Array of target states for transition definitions, nil for terminal states
    # @rbs throws RuntimeError -- When system is locked and cannot be modified
    # @rbs throws ArgumentError -- When transition hash is empty or contains multiple key-value pairs
    def add(state)
      raise "states cannot be added after locking" if @locked

      if state.is_a?(Hash)
        raise ArgumentError, "transition hash cannot be empty" if state.empty?
        raise ArgumentError, "transition hash must contain exactly one key-value pair, got #{state.size}: #{state.keys}" unless state.size == 1

        key, value = state.first
        # Allow nil keys/values since they convert to strings via to_s

        origin = key.to_s
        @transitions[origin] = normalize_states(value)
      else
        @transitions[state.to_s] = nil
      end
    end

    # Locks the transition system to prevent further modifications
    #
    # Locking is essential for StateJacket's two-layer architecture:
    # - Freezes the business rules (this layer) to ensure consistency
    # - Enables StateMachine creation with guaranteed valid states
    # - Provides thread safety through immutability
    #
    # Once locked, no new states or transitions can be added
    # Also freezes the internal data structures for immutability
    # @rbs return: bool -- Always returns true (idempotent operation)
    def lock
      return true if @locked
      @transitions.freeze
      @transitions.values.each { |value| value&.freeze }
      @locked = true
    end

    # Checks if the transition system is locked (preventing further modifications)
    # @rbs return: bool -- true if locked, false if still accepting new states/transitions
    def is_locked?
      !!@locked
    end

    # Checks if a transition is allowed according to the system's rules
    #
    # This method validates transitions against the business rules defined in this system.
    # Use it to verify state flows before implementing them in StateMachine event logic.
    #
    # Examples:
    #   system.can_transition?(pending: :approved)              # => true/false
    #   system.can_transition?(pending: [:approved, :rejected]) # => true if all valid
    #
    # Verifies that all target states are in the allowed transitions for the origin state
    # @rbs origin_to_destination: Hash[String | Symbol | BasicObject, (String | Symbol | BasicObject | Array[String | Symbol | BasicObject])] -- Single transition mapping: {origin_state => destination_state(s)} where values are converted to String via to_s
    # @rbs return: bool -- true if all specified transitions are allowed, false otherwise
    # @rbs throws ArgumentError -- When transition hash is empty, contains multiple key-value pairs, or argument is nil
    def can_transition?(origin_to_destination)
      raise ArgumentError, "transition argument cannot be nil" if origin_to_destination.nil?
      raise ArgumentError, "transition hash cannot be empty" if origin_to_destination.empty?
      raise ArgumentError, "transition hash must contain exactly one key-value pair, got #{origin_to_destination.size}: #{origin_to_destination.keys}" unless origin_to_destination.size == 1

      key, value = origin_to_destination.first
      # Allow nil keys/values since they convert to strings via to_s

      origin = key.to_s
      destinations = normalize_states(value)

      # Return false for undefined states or invalid transitions
      return false unless @transitions.key?(origin)

      allowed_states = @transitions[origin] || []
      (destinations & allowed_states).length == destinations.length
    end

    # Returns all state names defined in the system
    # Includes both transitioning states and terminal states
    # @rbs return: Array[String] -- Array of all state names in the system
    def states
      @transitions.keys
    end

    # Returns states that have outgoing transitions to other states
    # These are non-terminal states that can transition elsewhere
    # @rbs return: Array[String] -- Array of state names that have defined outgoing transitions
    def transitioners
      @transitions.keys.select { |state| !@transitions[state].nil? }
    end

    # Returns terminal states that have no outgoing transitions
    # These are end states that cannot transition to other states
    # @rbs return: Array[String] -- Array of terminal state names
    def terminators
      @transitions.keys.select { |state| @transitions[state].nil? }
    end

    # Checks if a given value is a valid state defined in the system
    # @rbs state: String | Symbol | BasicObject -- State to check (converted to String via to_s)
    # @rbs return: bool -- true if the state exists in the system, false otherwise
    def is_state?(state)
      @transitions.key? state.to_s
    end

    # Checks if a state is a terminal state with no outgoing transitions
    # @rbs state: String | Symbol | BasicObject -- State to check (converted to String via to_s)
    # @rbs return: bool -- true if the state is terminal, false if it has outgoing transitions or doesn't exist
    def is_terminator?(state)
      terminators.include?(state.to_s)
    end

    # Checks if a state has outgoing transitions to other states
    # @rbs state: String | Symbol | BasicObject -- State to check (converted to String via to_s)
    # @rbs return: bool -- true if the state has outgoing transitions, false if terminal or doesn't exist
    def is_transitioner?(state)
      transitioners.include?(state.to_s)
    end

    # Support for pattern matching on transition system properties
    # Enables: case system; in { states: ["pending", "approved"], locked?: true }; end
    # @rbs keys: Array[Symbol] -- The keys to extract for pattern matching
    # @rbs return: Hash[Symbol, Array[String] | bool]
    def deconstruct_keys(keys)
      {
        states: states,
        transitioners: transitioners,
        terminators: terminators,
        locked?: is_locked?
      }.slice(*keys)
    end

    private

    # Normalizes input values into an array of string state names
    # Single values are wrapped in an array, arrays are mapped to strings
    # Also ensures all referenced states exist in the transitions hash (as terminal states if not already defined)
    # @rbs values: (String | Symbol | BasicObject | Array[String | Symbol | BasicObject]) -- Single value or array of values to normalize (converted to String via to_s)
    # @rbs return: Array[String] -- Array of normalized state names
    def normalize_states(values)
      normalized = if values.respond_to?(:map)
        # Handle array case - allow nil values since they convert to strings
        values.map(&:to_s)
      else
        # Handle single value case
        [values.to_s]
      end

      # Auto-add referenced states as terminal states if not frozen
      normalized.each { |value| @transitions[value] ||= nil } unless @transitions.frozen?
      normalized
    end
  end
end
