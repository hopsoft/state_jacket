module StateJacket
  class StateMachine
    attr_reader :state

    def initialize(transition_system, state:)
      transition_system.lock
      raise ArgumentError.new("illegal state") unless transition_system.is_state?(state)
      @transition_system = transition_system
      @state = state.to_s
      @triggers = {}
    end

    def to_h
      triggers.dup
    end

    def events
      triggers.keys
    end

    def on(event, transitions={})
      raise "events cannot be added after locking" if is_locked?
      raise ArgumentError.new("event has already been added") if is_event?(event)
      transitions.each do |from, to|
        raise ArgumentError.new("illegal transition") unless transition_system.can_transition?(from => to)
        triggers[event.to_s] ||= []
        triggers[event.to_s] << { from.to_s => to.to_s }
        triggers[event.to_s].uniq!
      end
    end

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
    end

    def lock
      return true if is_locked?
      triggers.freeze
      triggers.values.map(&:freeze)
      triggers.values.freeze
      @locked = true
    end

    def is_locked?
      !!@locked
    end

    def is_event?(event)
      triggers.has_key? event.to_s
    end

    def can_trigger?(event)
      return false unless is_locked?
      !!transition_for(event)
    end

    private

      attr_reader :transition_system, :triggers

      def transition_for(event)
        triggers[event.to_s].find { |entry| entry.keys.first == state }
      end
  end
end
