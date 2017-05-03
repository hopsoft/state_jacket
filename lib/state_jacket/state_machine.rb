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
      raise "events cannot be added after locking" if is_locked?
      raise ArgumentError.new("event has already been added") if is_event?(event)
      transitions.each do |from, to|
        raise ArgumentError.new("illegal transition") unless transition_system.can_transition?(from => to)
        events[event.to_s] ||= []
        events[event.to_s] << { from.to_s => to.to_s }
        events[event.to_s].uniq!
      end
    end

    def trigger(event)
      raise "must be locked before triggering events" unless is_locked?
      raise ArgumentError.new("event not defined") unless is_event?(event)
      transition = transition_for(event)
      return unless transition
      from = @state
      to = transition.values.first
      raise "current state doesn't match transition state" unless from == transition.keys.first
      yield from, to if block_given?
      @state = to
    end

    def lock
      return true if is_locked?
      events.freeze
      events.values.map(&:freeze)
      events.values.freeze
      @locked = true
    end

    def is_locked?
      !!@locked
    end

    def is_event?(event)
      events.has_key? event.to_s
    end

    def can_trigger?(event)
      return false unless is_locked?
      !!transition_for(event)
    end

    private

      attr_reader :transition_system, :events

      def transition_for(event)
        events[event.to_s].find { |entry| entry.keys.first == state }
      end
  end
end
