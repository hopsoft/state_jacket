# frozen_string_literal: true

module StateJacket
  class StateMachine
    attr_reader :events
    attr_reader :state
    attr_reader :triggers

    def initialize(transition_system, state:)
      raise ArgumentError, "transition_system cannot be nil" if transition_system.nil?

      transition_system.lock
      raise ArgumentError, "illegal state '#{state}'. Available states: #{format_list(transition_system.states)}" unless transition_system.state?(state)
      @transition_system = transition_system
      @events = []
      @state = state.to_s
      @triggers = {}
      @transition_cache = {}
    end

    def states
      transition_system.states
    end

    def triggerable_events
      return [] unless @locked
      triggers.keys.select { |event| @transition_cache[[event, @state]] }
    end

    def reachable_states
      return [] unless locked?
      destinations = []
      triggers.keys.each do |event|
        transition = @transition_cache[[event, @state]]
        destinations << transition.values.first if transition
      end
      destinations.uniq
    end

    def active?
      @locked && !finished?
    end

    def finished?
      @transition_system.terminal? @state
    end

    def state_symbol
      state.to_sym
    end

    def on(event, transitions = {})
      raise "events cannot be added after locking" if @locked
      raise ArgumentError, "transitions cannot be nil" if transitions.nil?
      raise ArgumentError, "event '#{event}' already exists with transitions: #{triggers[event.to_s]}" if triggers.has_key?(event.to_s)

      event = event.to_s
      payload = {}

      transitions.each do |from, to|
        case from
        in Array then from.each { |state| payload[state.to_s] = to.to_s }
        else payload[from.to_s] = to.to_s
        end
      end

      payload.each do |from, to|
        validate_transition!(from, to)

        triggers[event] ||= Set.new
        transition = {from => to}
        triggers[event] << transition

        @transition_cache[[event_str, from_str]] = transition
      end
    end

    def trigger(event)
      raise "must be locked before triggering events" unless @locked

      event_str = event.to_s
      raise ArgumentError, "event '#{event_str}' not defined. Available events: #{format_list(triggers.keys)}" unless triggers.has_key?(event_str)

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

    def lock
      return true if @locked
      triggers.freeze
      triggers.values.map(&:freeze)
      triggers.values.freeze
      @events = triggers.keys.freeze
      @transition_cache.freeze
      @locked = true
    end

    def locked?
      !!@locked
    end

    def event?(event)
      triggers.has_key? event.to_s
    end

    def can_trigger?(event)
      return false unless @locked
      !!@transition_cache[[event.to_s, @state]]
    end

    def deconstruct_keys(keys)
      keys&.any? ? to_h.slice(*keys) : to_h
    end

    def to_h
      @transition_system.terminal?(@state)
      triggers.merge(
        state: state,
        locked: locked?,
        active: active?,
        finished: finished?,
        reachable_states: reachable_states,
        triggerable_events: triggerable_events
      )
    end

    private

    attr_reader :transition_system

    def transition_for(event)
      @transition_cache[[event.to_s, state]]
    end

    def format_list(list)
      list.empty? ? "none" : list.join(", ")
    end

    def validate_transition!(from, to)
      return if @transition_system.allows?(from => to)

      from_str, to_str = from.to_s, to.to_s
      unless @transition_system.state?(from_str)
        raise ArgumentError, "illegal transition: from state '#{from_str}' is not defined in the transition rules"
      end

      allowed = @transition_system.to_h[:rules][from_str] || []
      tos = allowed.nil? ? "none (terminal state)" : allowed.join(", ")
      raise ArgumentError, "illegal transition from '#{from_str}' to '#{to_str}'. Allowed transitions: #{tos}"
    end
  end
end
