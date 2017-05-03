module StateJacket
  class StateMachine
    attr_reader :state

    def initialize(transition_system, state:)
      transition_system.lock
      raise ArgumentError.new("illegal state") unless transition_system.is_state?(state)
      @transition_system = transition_system
      @state = state.to_s
      @events = {}
    end

    def to_h
      {
        "transitions" => transition_system.to_h, # system that establishes allowed transitions
        "events" => events.dup                   # allowed events that perform transitions
      }
    end

    def on(event, transitions={})
      raise ArgumentError.new("events cannot be added after locking") if locked?
      raise ArgumentError.new("event has already been added") if is_event?(event)
      transitions.each do |from, to|
        raise ArgumentError.new("illegal transition") unless transition_system.can_transition?(from => to)
        events[event.to_s] ||= []
        events[event.to_s] << { from.to_s => to.to_s }
        events[event.to_s].uniq!
      end
    end

    def trigger(event)
      raise ArgumentError.new("event not defined") unless is_event?(event)
      transition = transition_for(event)
      return unless transition
      next_state = transition.values.first
      yield if block_given?
      @state = next_state
    end

    def lock
      return true if locked?
      events.freeze
      events.values.map(&:freeze)
      events.values.freeze
      @locked = true
    end

    def locked?
      !!@locked
    end

    def is_event?(event)
      events.has_key? event.to_s
    end

    private

      attr_reader :transition_system, :events

      def transition_for(event)
        events[event.to_s].find { |entry| entry.keys.first == state }
      end
  end
end
