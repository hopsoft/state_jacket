# frozen_string_literal: true

module StateJacket
  class StateMachine
    # @rbs @transition_system: StateTransitionSystem -- The underlying state transition system
    # @rbs @state: String -- Current state (always normalized to String via to_s)
    # @rbs @triggers: Hash[String, Array[Hash[String, String]]] -- Event name to transition mappings
    # @rbs @transition_cache: Hash[[String, String], Hash[String, String]] -- Pre-computed cache for O(1) transition lookup: [event, state] => transition
    # @rbs @locked: bool? -- Whether the state machine is locked (prevents adding new events)
    attr_reader :state #: String # standard:disable Layout/LeadingCommentSpace

    # Initializes a new state machine with a transition system and initial state
    # The transition system is automatically locked during initialization to prevent
    # further modifications to the allowed states and transitions
    # @rbs transition_system: StateTransitionSystem -- The state transition system defining valid states and transitions
    # @rbs state: String | Symbol | BasicObject -- The initial state (converted to String via to_s)
    # @rbs return: void
    # @rbs throws ArgumentError -- When the initial state is not defined in the transition system
    def initialize(transition_system, state:)
      raise ArgumentError, "transition_system cannot be nil" if transition_system.nil?

      transition_system.lock
      raise ArgumentError, "illegal state '#{state}'. Available states: #{format_list(transition_system.states)}" unless transition_system.is_state?(state)
      @transition_system = transition_system
      @state = state.to_s
      @triggers = {}
      @transition_cache = {}
    end

    # Returns a duplicate of the internal triggers hash for inspection
    # Each key is an event name (String), each value is an array of state transitions
    # where each transition is a hash with one key-value pair: from_state => to_state
    # @rbs return: Hash[String, Array[Hash[String, String]]]
    def to_h
      triggers.dup
    end

    # Returns all event names that have been defined in the state machine
    # @rbs return: Array[String] -- Array of event names (converted to String via to_s during definition)
    def events
      triggers.keys
    end

    # Returns all state names from the transition system
    # @rbs return: Array[String] -- Array of state names from the transition system
    def states
      transition_system.states
    end

    # Returns all events that can be triggered from the current state
    # Only includes events that are valid for the current state when the machine is locked
    # @rbs return: Array[String] -- Array of event names that can be triggered from current state
    def triggerable_events
      return [] unless is_locked?
      events.select { |event| can_trigger?(event) }
    end

    # Returns all possible destination states from the current state
    # Shows where the state machine can transition to from its current state
    # @rbs return: Array[String] -- Array of state names that can be reached from current state
    def reachable_states
      triggerable_events.map { |event|
        transition = transition_for(event)
        transition&.values&.first
      }.compact.uniq
    end

    # Checks if the state machine is currently in a terminal state
    # Terminal states have no outgoing transitions defined in the transition system
    # @rbs return: bool -- true if current state is terminal, false if it has outgoing transitions
    def terminal?
      transition_system.is_terminator?(state)
    end

    # Returns the current state as a symbol for convenience
    # Useful when working with APIs that expect symbols rather than strings
    # @rbs return: Symbol -- Current state converted to symbol
    def state_symbol
      state.to_sym
    end

    # Defines an event with its associated state transitions
    # All transitions must be valid according to the underlying state transition system
    # The state machine must not be locked when adding events
    # @rbs event: String | Symbol | BasicObject -- The event name (converted to String via to_s)
    # @rbs transitions: Hash[String | Symbol | BasicObject, String | Symbol | BasicObject] -- Hash mapping from_state => to_state (both converted to String via to_s)
    # @rbs return: void
    # @rbs throws RuntimeError -- When events cannot be added after locking
    # @rbs throws ArgumentError -- When event already exists or when transition is not allowed by the transition system
    def on(event, transitions = {})
      raise "events cannot be added after locking" if is_locked?
      raise ArgumentError, "transitions cannot be nil" if transitions.nil?
      raise ArgumentError, "event '#{event}' already exists with transitions: #{triggers[event.to_s]}" if is_event?(event)

      transitions.each do |from, to|
        validate_transition!(from, to)
        event_str = event.to_s
        from_str = from.to_s
        to_str = to.to_s

        triggers[event_str] ||= []
        transition_hash = {from_str => to_str}
        triggers[event_str] << transition_hash
        triggers[event_str].uniq!

        # Build transition cache for O(1) access
        @transition_cache[[event_str, from_str]] = transition_hash
      end
    end

    # Triggers an event to transition the state machine to a new state
    # Returns nil if the event cannot be triggered from the current state
    # The state machine must be locked before triggering events
    # @rbs event: String | Symbol | BasicObject -- The event to trigger (converted to String via to_s)
    # @rbs &block: ? (String, String) -> void -- Optional block called during transition, receives (from_state, to_state)
    # @rbs return: String? -- The new state after transition, or nil if transition is not possible
    # @rbs throws RuntimeError -- When state machine is not locked before triggering events
    # @rbs throws ArgumentError -- When the event is not defined in the state machine
    def trigger(event)
      raise "must be locked before triggering events" unless is_locked?
      raise ArgumentError, "event '#{event}' not defined. Available events: #{format_list(events)}" unless is_event?(event)

      transition = transition_for(event)
      return nil unless transition

      from = @state
      to = transition.values.first
      raise "internal error: current state '#{from}' doesn't match transition source state '#{transition.keys.first}'" unless from == transition.keys.first

      yield from, to if block_given?
      @state = to
      to
    end

    # Locks the state machine to prevent further event definitions
    # Once locked, no new events can be added, but existing events can be triggered
    # This also freezes the internal triggers data structure for immutability
    # @rbs return: bool -- Always returns true (idempotent operation)
    def lock
      return true if is_locked?
      triggers.freeze
      triggers.values.map(&:freeze)
      triggers.values.freeze
      @transition_cache.freeze
      @locked = true
    end

    # Checks if the state machine is locked (preventing addition of new events)
    # @rbs return: bool -- true if locked, false if still accepting new event definitions
    def is_locked?
      !!@locked
    end

    # Checks if an event has been defined in the state machine
    # @rbs event: String | Symbol | BasicObject -- The event to check (converted to String via to_s)
    # @rbs return: bool -- true if the event is defined, false otherwise
    def is_event?(event)
      triggers.has_key? event.to_s
    end

    # Checks if an event can be triggered from the current state
    # Returns false if the state machine is not locked or if no valid transition exists
    # @rbs event: String | Symbol | BasicObject -- The event to check (converted to String via to_s)
    # @rbs return: bool -- true if the event can be triggered from current state, false otherwise
    def can_trigger?(event)
      return false unless is_locked?
      !!transition_for(event)
    end

    private

    attr_reader :transition_system #: StateTransitionSystem # standard:disable Layout/LeadingCommentSpace
    attr_reader :triggers #: Hash[String, Array[Hash[String, String]]] # standard:disable Layout/LeadingCommentSpace

    # Finds the specific transition for an event from the current state
    # Uses pre-computed transition cache for O(1) access instead of O(n) search
    # @rbs event: String | Symbol | BasicObject -- The event to find transition for (converted to String via to_s)
    # @rbs return: Hash[String, String]? -- Single transition hash {from_state => to_state} or nil if not found
    def transition_for(event)
      @transition_cache[[event.to_s, state]]
    end

    # Formats an array as a string for error messages
    # @rbs list: Array[String] -- Array of items to format
    # @rbs return: String -- Formatted list or "none" if empty
    def format_list(list)
      list.empty? ? "none" : list.join(", ")
    end

    # Validates that a transition is allowed by the transition system
    # Raises descriptive ArgumentError if the transition is invalid
    # @rbs from: String | Symbol | BasicObject -- Source state (converted to String via to_s)
    # @rbs to: String | Symbol | BasicObject -- Destination state (converted to String via to_s)
    # @rbs return: void
    # @rbs throws ArgumentError -- When transition is not allowed or source state is undefined
    def validate_transition!(from, to)
      return if transition_system.can_transition?(from => to)

      from_str, to_str = from.to_s, to.to_s
      unless transition_system.is_state?(from_str)
        raise ArgumentError, "illegal transition: source state '#{from_str}' is not defined in the transition system"
      end

      allowed = transition_system.to_h[from_str] || []
      destinations = allowed.empty? ? "none (terminal state)" : allowed.join(", ")
      raise ArgumentError, "illegal transition from '#{from_str}' to '#{to_str}'. Allowed destinations: #{destinations}"
    end
  end
end
