# frozen_string_literal: true

module StateJacket
  # Machine implements a state machine based on a defined Matrix.
  #
  # A state machine:
  # - Tracks the current state from the set of allowed states
  # - Defines events that trigger transitions between states
  # - Enforces that transitions follow the rules of the underlying matrix
  # - Provides introspection methods to query available events and states
  # - Supports long-running processes and workflow resumption
  # - Allows matrix and event definitions to evolve between pauses
  #
  # Once a state machine is locked, it can only execute transitions, not define new ones.
  #
  class Machine
    include MonitorMixin

    class Error < StandardError; end

    class << self
      # Creates a new Machine from a hash representation.
      #
      # This method facilitates persistence and restoration of state machines
      # for long-running processes that span multiple sessions.
      #
      # Alias: from_h
      #
      # @example Creating from a hash representation
      #   matrix = StateJacket::Matrix.from_hash(matrix_hash)
      #   hash = existing_machine.to_hash
      #   machine = Machine.from_hash(matrix, hash)
      #
      # @rbs matrix: Matrix
      # @rbs hash: Hash[Symbol | String, Object]
      # @rbs return: Machine
      def from_hash(matrix, hash)
        current_state = hash[:current_state] || hash["current_state"]
        raise Error, "Hash must contain a 'current_state' key" unless current_state

        machine = new(matrix, current_state: current_state)
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

    # @rbs @matrix: Matrix
    # @rbs @current_state: String
    # @rbs @states: Array[String]
    # @rbs @cache: Hash[[String, String], Hash[String, String]]
    # @rbs @events: Array[String]
    # @rbs @rules: Hash[String, Array[Hash[String, String]]]
    # @rbs @locked: bool

    # standard:disable Layout/LeadingCommentSpace
    attr_reader :events #: Array[String] -- List of all defined event names
    attr_reader :states #: Array[String] -- List of all available states defined in the matrix
    attr_reader :matrix #: Matrix -- The underlying state matrix that governs allowed state transitions
    # standard:enable Layout/LeadingCommentSpace

    # --------------------------------------------------------------------------
    # Core Initialization and State Methods
    # --------------------------------------------------------------------------

    # Initializes a new Machine with a state matrix and initial state.
    #
    # @rbs matrix: Matrix
    # @rbs current_state: String | Symbol
    # @rbs return: void
    def initialize(matrix, current_state:)
      super()

      raise Error, "matrix cannot be nil" if matrix.nil?

      unless matrix.include?(current_state)
        raise Error, "illegal state '#{current_state}'. Available states: #{matrix.states.inspect}"
      end

      @matrix = matrix.lock
      @current_state = current_state.to_s
      @states = matrix.states

      @cache = {}
      @events = []
      @rules = {}
    end

    # Returns the current state of the state machine.
    # Reading @current_state is safe without synchronization since:
    # - String reads are atomic in Ruby
    # - @current_state is only modified within synchronized blocks
    #
    # @rbs return: String
    attr_reader :current_state

    # Returns a copy of the rules mapping.
    # This provides thread-safe access to the current rule definitions.
    #
    # @rbs return: Hash[String, Array[Hash[String, String]]]
    def rules
      synchronize { @rules.dup }
    end

    # Returns true if the current state is a terminal state (has no outgoing transitions).
    #
    # @rbs return: bool
    def finished?
      matrix.terminal? current_state
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
      synchronize do
        raise Error, "events cannot be added after locking" if @locked
        raise Error, "transitions cannot be nil" if transitions.nil?

        event = event.to_s
        @rules[event] ||= []

        payload = transitions.each_with_object({}) do |(from, to), memo|
          case from
          in Array then from.each { memo[it.to_s] = to.to_s }
          else memo[from.to_s] = to.to_s
          end
        end

        payload.each do |from, to|
          raise Error, "illegal transition: {'#{from}' => '#{to}'} " unless matrix.allows?(from => to)

          transition = {from => to}
          index = @rules[event].index { it.keys.first == from }
          index ?
            @rules[event][index] = transition :
            @rules[event] << transition

          @cache[[event, from]] = transition
        end
      end

      self
    end

    # Triggers an event, causing a state transition if possible.
    # If a block is given, it is called with the from and to states before the transition occurs.
    #
    # @rbs event: String | Symbol
    # @rbs return: Transition
    def trigger(event)
      synchronize do
        raise Error, "must be locked before triggering events" unless @locked

        event = event.to_s
        raise Error, "event '#{event}' not defined. Available events: #{@rules.keys.inspect}" unless @rules.key?(event.to_s)

        transition = @cache[[event, @current_state]]
        raise Error, "transition not found for '#{event}' + '#{@current_state}'" unless transition

        from = @current_state
        to = transition.values.first

        begin
          yield from, to if block_given?
          @current_state = to
          Transition.new event, from, to, :ok
        rescue => error
          Transition.new event, from, to, :error, error
        end
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

      synchronize do
        @rules.values.each do
          it.each(&:freeze)
          it.freeze
        end
        @rules.freeze
        @events = @rules.keys.freeze
        @cache.freeze
        @locked = true
      end

      self
    end

    # Returns true if the state machine is locked.
    # Reading @locked is safe without synchronization since:
    # - Boolean reads are atomic in Ruby
    # - @locked is only modified within synchronized blocks
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
        rules: rules
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
      synchronize { @rules.key? event.to_s }
    end

    # Returns true if the given event can be triggered from the current state.
    # Always returns false if the machine is not locked.
    #
    # @rbs event: String | Symbol
    # @rbs return: bool
    def can_trigger?(event)
      return false unless locked?
      synchronize { !!@cache[[event.to_s, @current_state]] }
    end

    # Returns an array of events that can be triggered from the current state.
    # Returns an empty array if the machine is not locked.
    #
    # @rbs return: Array[String]
    def triggerable_events
      return [] unless locked?
      synchronize { @rules.keys.select { @cache[[it, @current_state]] } }
    end

    # Returns an array of states that can be reached from the current state
    # by triggering available events.
    # Returns an empty array if the machine is not locked.
    #
    # @rbs return: Array[String]
    def reachable_states
      return [] unless locked?

      synchronize do
        states = @rules.keys.each_with_object(Set.new) do |event, memo|
          transition = @cache[[event, @current_state]]
          memo << transition.values.first if transition
        end

        states.to_a
      end
    end
  end
end
