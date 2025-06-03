# frozen_string_literal: true

module StateJacket
  # StateMachine is the behavior engine in StateJacket's two-layer architecture.
  #
  # While StateTransitionSystem defines the "rules" (what transitions are valid),
  # StateMachine manages the "behavior" (current state and event-driven transitions).
  #
  # This separation enables:
  # - Independent testing of business rules vs. event logic
  # - Reusing the same transition rules across multiple machines
  # - Clear separation between state validation and application behavior
  #
  # THREAD SAFETY:
  # StateMachine becomes immutable after locking, making it safe for concurrent access.
  # The pre-computed transition cache provides O(1) event lookups regardless of complexity.
  #
  # ELEGANT EVENT SYNTAX:
  #   machine.on :event, from: :to                                            # Single transition
  #   machine.on :event, {:from1 => :to, :from2 => :to}                      # Multiple transitions
  #   machine.on :event, [:from1, :from2] => :to                             # Array syntax
  class StateMachine
    # @rbs @transition_system: StateTransitionSystem -- The underlying state transition system
    # @rbs @state: String -- Current state (always normalized to String via to_s)
    # @rbs @triggers: Hash[String, Array[Hash[String, String]]] -- Event name to transition mappings
    # @rbs @transition_cache: Hash[[String, String], Hash[String, String]] -- Pre-computed cache for O(1) transition lookup: [event, state] => transition
    # @rbs @locked: bool -- Whether the state machine is locked (prevents adding new events)
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
      @triggers.dup
    end

    # Returns all event names that have been defined in the state machine
    # @rbs return: Array[String] -- Array of event names (converted to String via to_s during definition)
    def events
      @triggers.keys
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
      return [] unless @locked
      @triggers.keys.select { |event| @transition_cache[[event, @state]] }
    end

    # Returns all possible destination states from the current state
    # Shows where the state machine can transition to from its current state
    # @rbs return: Array[String] -- Array of state names that can be reached from current state
    def reachable_states
      return [] unless @locked
      destinations = []
      @triggers.keys.each do |event|
        transition = @transition_cache[[event, @state]]
        destinations << transition.values.first if transition
      end
      destinations.uniq
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
    #
    # Supports multiple syntaxes for defining state transitions:
    #   machine.on :event, state: :to                         # Single from state
    #   machine.on :event, {state1: :dest1, state2: :dest2}   # Multiple from states, different destinations
    #   machine.on :event, [:state1, :state2] => :to          # Multiple from states, same destination (elegant array syntax)
    #
    # @rbs event: String | Symbol | BasicObject -- The event name (converted to String via to_s)
    # @rbs transitions: Hash[String | Symbol | BasicObject | Array[String | Symbol | BasicObject], String | Symbol | BasicObject] -- Hash mapping from_state(s) => to_state. Keys can be arrays to specify multiple from states for the same destination (all converted to String via to_s)
    # @rbs return: void
    # @rbs throws RuntimeError -- When events cannot be added after locking
    # @rbs throws ArgumentError -- When event already exists or when transition is not allowed by the transition system
    def on(event, transitions = {})
      raise "events cannot be added after locking" if @locked
      raise ArgumentError, "transitions cannot be nil" if transitions.nil?
      raise ArgumentError, "event '#{event}' already exists with transitions: #{@triggers[event.to_s]}" if @triggers.has_key?(event.to_s)

      # Expand array keys into individual transitions
      expanded_transitions = {}
      transitions.each do |origin, destination|
        if origin.is_a?(Array)
          # Handle elegant array syntax: [:state1, :state2] => :to
          origin.each do |origin_state|
            expanded_transitions[origin_state] = destination
          end
        else
          # Handle single from syntax: :state1 => :to
          expanded_transitions[origin] = destination
        end
      end

      expanded_transitions.each do |origin, destination|
        validate_transition!(origin, destination)
        event_str = event.to_s
        origin_str = origin.to_s
        destination_str = destination.to_s

        @triggers[event_str] ||= []
        transition_hash = {origin_str => destination_str}
        @triggers[event_str] << transition_hash
        @triggers[event_str].uniq!

        # Build transition cache for O(1) access
        @transition_cache[[event_str, origin_str]] = transition_hash
      end
    end

    # Triggers an event to transition the state machine to a new state
    # Returns a TransitionResult object indicating success/failure and transition details
    # The state machine must be locked before triggering events
    # @rbs event: String | Symbol | BasicObject -- The event to trigger (converted to String via to_s)
    # @rbs &block: ^(String, String) -> void -- Optional block called during transition, receives (from_state, to_state)
    # @rbs return: TransitionResult -- Result object with transition details and success status
    # @rbs throws RuntimeError -- When state machine is not locked before triggering events
    # @rbs throws ArgumentError -- When the event is not defined in the state machine
    def trigger(event)
      raise "must be locked before triggering events" unless @locked

      event_str = event.to_s
      raise ArgumentError, "event '#{event_str}' not defined. Available events: #{format_list(@triggers.keys)}" unless @triggers.has_key?(event_str)

      transition = @transition_cache[[event_str, @state]]

      unless transition
        return TransitionResult.new(false, @state, nil, event_str)
      end

      origin = @state
      destination = transition.values.first

      yield origin, destination if block_given?
      @state = destination
      TransitionResult.new(true, origin, destination, event_str)
    end

    # Locks the state machine to prevent further event definitions
    # Once locked, no new events can be added, but existing events can be triggered
    # This also freezes the internal triggers data structure for immutability
    # @rbs return: bool -- Always returns true (idempotent operation)
    def lock
      return true if @locked
      @triggers.freeze
      @triggers.values.map(&:freeze)
      @triggers.values.freeze
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
      @triggers.has_key? event.to_s
    end

    # Checks if an event can be triggered from the current state
    # Returns false if the state machine is not locked or if no valid transition exists
    # @rbs event: String | Symbol | BasicObject -- The event to check (converted to String via to_s)
    # @rbs return: bool -- true if the event can be triggered from current state, false otherwise
    def can_trigger?(event)
      return false unless @locked
      !!@transition_cache[[event.to_s, @state]]
    end

    # Support for pattern matching on machine state and properties
    # Enables: case machine; in { state: "pending", actions: ["submit"] }; end
    # @rbs keys: Array[Symbol] -- The keys to extract for pattern matching
    # @rbs return: Hash[Symbol, String | Array[String] | bool]
    def deconstruct_keys(keys)
      {
        # Core state information
        state: @state,
        actions: triggerable_events,
        destinations: reachable_states,

        # Status flags
        locked?: @locked,
        terminal?: @transition_system.is_terminator?(@state),
        active?: @locked && !@transition_system.is_terminator?(@state),

        # Legacy aliases for backward compatibility
        events: @triggers.keys,
        triggerable_events: triggerable_events,
        reachable_states: reachable_states
      }.slice(*keys)
    end

    # Simple pattern matching support using case equality
    # Use these in case statements for clean, idiomatic pattern matching
    module Patterns
      # Match terminal state machines (no outgoing transitions)
      # Usage: case machine; in Terminal; end
      Terminal = ->(machine) { machine.is_a?(StateMachine) && machine.terminal? }

      # Match active machines (locked and not terminal)
      # Usage: case machine; in Active; end
      Active = ->(machine) {
        machine.is_a?(StateMachine) && machine.is_locked? && !machine.terminal?
      }

      # Match machines that can trigger a specific action
      # Usage: case machine; in PendingAction[:submit]; end
      PendingAction = ->(action) do
        ->(machine) {
          machine.is_a?(StateMachine) &&
            machine.is_locked? &&
            machine.can_trigger?(action)
        }
      end

      # Match machines in a specific state
      # Usage: case machine; in InState[:pending]; end
      InState = ->(state) do
        ->(machine) {
          machine.is_a?(StateMachine) && machine.state == state.to_s
        }
      end

      # Match machines that can reach a specific state
      # Usage: case machine; in CanReach[:completed]; end
      CanReach = ->(state) do
        ->(machine) {
          machine.is_a?(StateMachine) &&
            machine.is_locked? &&
            machine.reachable_states.include?(state.to_s)
        }
      end
    end

    private

    attr_reader :transition_system #: StateTransitionSystem # standard:disable Layout/LeadingCommentSpace

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
    # @rbs origin: String | Symbol | BasicObject -- From state (converted to String via to_s)
    # @rbs destination: String | Symbol | BasicObject -- To state (converted to String via to_s)
    # @rbs return: void
    # @rbs throws ArgumentError -- When transition is not allowed or source state is undefined
    def validate_transition!(origin, destination)
      return if @transition_system.can_transition?(origin => destination)

      origin_str, destination_str = origin.to_s, destination.to_s
      unless @transition_system.is_state?(origin_str)
        raise ArgumentError, "illegal transition: from state '#{origin_str}' is not defined in the transition system"
      end

      allowed = @transition_system.to_h[origin_str] || []
      destinations = allowed.empty? ? "none (terminal state)" : allowed.join(", ")
      raise ArgumentError, "illegal transition from '#{origin_str}' to '#{destination_str}'. Allowed destinations: #{destinations}"
    end
  end
end
