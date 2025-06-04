# frozen_string_literal: true

module StateJacket
  # StateMachine implements a state machine based on a defined TransitionSystem.
  #
  # A state machine:
  # - Tracks the current state from the set of allowed states
  # - Defines events that trigger transitions between states
  # - Enforces that transitions follow the rules of the underlying transition system
  # - Provides introspection methods to query available events and states
  # - Supports long-running processes and workflow resumption
  # - Allows transition system and event definitions to evolve between pauses
  #
  # Once a state machine is locked, it can only execute transitions, not define new ones.
  #
  # Workflow Resumption:
  # StateMachine supports pausing and resuming workflows across process boundaries.
  # This is particularly useful for long-running processes that may span days,
  # weeks, or months and need to persist state between executions.
  #
  # A key feature is that both the transition system and state machine event definitions
  # can evolve between pauses, allowing workflows to adapt to changing requirements:
  #
  # ```ruby
  # # Day 1: Start workflow with initial transition system
  # initial_system = create_transition_system
  # machine = StateMachine.new(initial_system, current_state: :submitted)
  # # ... define events and transitions
  # machine.lock
  # machine.trigger(:review)
  #
  # # Save state to persistent storage
  # saved_state = machine.current_state # => "under_review"
  #
  # # Day 3: Resume workflow with an evolved transition system
  # evolved_system = create_evolved_transition_system  # System with new/changed states
  # resumed_machine = StateMachine.new(evolved_system, current_state: saved_state)
  # # ... define potentially different events for current state
  # resumed_machine.lock
  # # ... continue workflow with new capabilities
  # ```
  #
  # This evolution capability is powerful but requires careful management to ensure
  # that saved states remain valid in evolved systems.
  #
  class StateMachine
    class << self
      # Creates a new StateMachine from a hash representation.
      #
      # This method facilitates persistence and restoration of state machines
      # for long-running processes that span multiple sessions.
      #
      # Alias: from_h
      #
      # @example Creating from a hash representation
      #   system = StateJacket::TransitionSystem.from_hash(system_hash)
      #   hash = existing_machine.to_hash
      #   machine = StateMachine.from_hash(system, hash)
      #
      # @rbs transition_system: TransitionSystem
      # @rbs hash: Hash[Symbol | String, Object]
      # @rbs return: StateMachine
      def from_hash(transition_system, hash)
        current_state = hash[:current_state] || hash["current_state"]
        raise ArgumentError, "Hash must contain a 'current_state' key" unless current_state

        machine = new(transition_system, current_state: current_state)
        rules = hash[:rules] || hash["rules"] || []

        rules.each do |event, transitions|
          transitions.each do |transition|
            from, to = transition.to_a.first
            machine.on(event, from => to)
          end
        end

        locked = hash[:locked] || hash["locked"]
        machine.lock if locked

        machine
      end

      alias_method :from_h, :from_hash
    end

    # @rbs @transition_system: TransitionSystem
    # @rbs @current_state: String
    # @rbs @states: Array[String]
    # @rbs @cache: Hash[[String, String], Hash[String, String]]
    # @rbs @events: Array[String]
    # @rbs @rules: Hash[String, Array[Hash[String, String]]]
    # @rbs @locked: bool

    # standard:disable Layout/LeadingCommentSpace
    attr_reader :current_state #: String -- The current state of the state machine
    attr_reader :events #: Array[String] -- List of all defined event names
    attr_reader :rules #: Hash[String, Array[Hash[String, String]]] -- Mapping of event names to their transition rules
    attr_reader :states #: Array[String] -- List of all available states in the transition system
    attr_reader :transition_system #: TransitionSystem -- The underlying transition system that governs allowed transitions
    # standard:enable Layout/LeadingCommentSpace

    # --------------------------------------------------------------------------
    # Core Initialization and State Methods
    # --------------------------------------------------------------------------

    # Initializes a new StateMachine with a transition system and initial state.
    #
    # @rbs transition_system: TransitionSystem
    # @rbs current_state: String | Symbol
    # @rbs return: void
    def initialize(transition_system, current_state:)
      raise ArgumentError, "transition_system cannot be nil" if transition_system.nil?

      unless transition_system.include?(current_state)
        raise ArgumentError, "illegal state '#{current_state}'. Available states: #{transition_system.states.inspect}"
      end

      @transition_system = transition_system.lock
      @current_state = current_state.to_s
      @states = transition_system.states

      @cache = {}
      @events = []
      @rules = {}
    end

    # Returns true if the current state is a terminal state (has no outgoing transitions).
    #
    # @rbs return: bool
    def finished?
      transition_system.terminal? current_state
    end

    # --------------------------------------------------------------------------
    # Core Event Definition and Triggering Methods
    # --------------------------------------------------------------------------

    # Defines an event and its associated state transitions.
    # Transitions are defined as a mapping of source states to target states.
    #
    # @rbs event: String | Symbol
    # @rbs transitions: Hash[String | Symbol | Array[String | Symbol], String | Symbol]
    # @rbs return: self
    def on(event, transitions = {})
      raise "events cannot be added after locking" if locked?
      raise ArgumentError, "transitions cannot be nil" if transitions.nil?

      event = event.to_s
      rules[event] ||= []

      payload = transitions.each_with_object({}) do |(from, to), memo|
        case from
        in Array then from.each { memo[it.to_s] = to.to_s }
        else memo[from.to_s] = to.to_s
        end
      end

      payload.each do |from, to|
        raise ArgumentError, "illegal transition: {'#{from}' => '#{to}'} " unless transition_system.allows?(from => to)

        transition = {from => to}
        index = rules[event].index { it.keys.first == from }
        index ?
          rules[event][index] = transition :
          rules[event] << transition

        @cache[[event, from]] = transition
      end

      self
    end

    # Triggers an event, causing a state transition if possible.
    # If a block is given, it is called with the from and to states before the transition occurs.
    #
    # @rbs event: String | Symbol
    # @rbs return: TransitionResult
    def trigger(event)
      raise "must be locked before triggering events" unless locked?

      event = event.to_s
      raise ArgumentError, "event '#{event}' not defined. Available events: #{rules.keys.inspect}" unless include?(event)

      transition = @cache[[event, current_state]]
      raise ArgumentError, "transition not found for '#{event}' + '#{current_state}'" unless transition

      from = current_state
      to = transition.values.first

      begin
        yield from, to if block_given?
        @current_state = to
        TransitionResult.new event, from, to, :ok
      rescue => error
        TransitionResult.new event, from, to, :error, error
      end
    end

    # --------------------------------------------------------------------------
    # System Control Methods
    # --------------------------------------------------------------------------

    # Locks the state machine, preventing further modifications to events and transitions.
    # A machine must be locked before events can be triggered.
    #
    # @rbs return: self
    def lock
      return self if locked?
      rules.values.each do
        it.each(&:freeze)
        it.freeze
      end
      rules.freeze
      @events = rules.keys.freeze
      @cache.freeze
      @locked = true
      self
    end

    # Returns true if the state machine is locked.
    #
    # @rbs return: bool
    def locked?
      !!@locked
    end

    # --------------------------------------------------------------------------
    # Serialization Methods
    # --------------------------------------------------------------------------

    # Supports pattern matching by allowing the state machine to be deconstructed into a hash.
    # If keys is provided, only those keys will be included in the resulting hash.
    #
    # @rbs keys: Array[Symbol]?
    # @rbs return: Hash[Symbol, Object]
    def deconstruct_keys(keys)
      keys&.any? ? to_hash.slice(*keys) : to_hash
    end

    # Returns a comprehensive hash representation of the state machine.
    # This includes lock status, current state, finish status, reachable states,
    # triggerable events, and the complete rule map.
    #
    # Alias: to_h
    #
    # @rbs return: Hash[Symbol, Object]
    def to_hash
      {
        locked: locked?,
        current_state: current_state,
        finished: finished?,
        reachable_states: reachable_states,
        triggerable_events: triggerable_events,
        rules: rules.dup
      }
    end

    alias_method :to_h, :to_hash

    # --------------------------------------------------------------------------
    # Query/Introspection Methods
    # --------------------------------------------------------------------------

    # Returns true if the given event is defined in this state machine.
    #
    # @rbs event: String | Symbol
    # @rbs return: bool
    def include?(event)
      rules.key? event.to_s
    end

    # Returns true if the given event can be triggered from the current state.
    # Always returns false if the machine is not locked.
    #
    # @rbs event: String | Symbol
    # @rbs return: bool
    def can_trigger?(event)
      return false unless locked?
      !!@cache[[event.to_s, current_state]]
    end

    # Returns an array of events that can be triggered from the current state.
    # Returns an empty array if the machine is not locked.
    #
    # @rbs return: Array[String]
    def triggerable_events
      return [] unless locked?
      rules.keys.select { @cache[[it, current_state]] }
    end

    # Returns an array of states that can be reached from the current state
    # by triggering available events.
    # Returns an empty array if the machine is not locked.
    #
    # @rbs return: Array[String]
    def reachable_states
      return [] unless locked?

      states = rules.keys.each_with_object(Set.new) do |event, memo|
        transition = @cache[[event, current_state]]
        memo << transition.values.first if transition
      end

      states.to_a
    end
  end
end
