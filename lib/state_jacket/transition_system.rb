module StateJacket
  class TransitionSystem
    def initialize
      @transitions = {}
    end

    def to_h
      transitions.dup
    end

    def add(state)
      raise "states cannot be added after locking" if is_locked?
      if state.is_a?(Hash)
        from = state.keys.first.to_s
        transitions[from] = make_states(state.values.first)
      else
        transitions[state.to_s] = nil
      end
    end

    def lock
      return true if is_locked?
      transitions.freeze
      transitions.values.each { |value| value.freeze unless value.nil? }
      @locked = true
    end

    def is_locked?
      !!@locked
    end

    def can_transition?(from_to)
      raise ArgumentError.new("from_to should contain a single transition") unless from_to.size == 1
      from = from_to.keys.first.to_s
      to = make_states(from_to.values.first)
      allowed_states =  transitions[from] || []
      (to & allowed_states).length == to.length
    end

    def states
      transitions.keys
    end

    def transitioners
      transitions.keys.select { |state| transitions[state] != nil }
    end

    def terminators
      transitions.keys.select { |state| transitions[state] == nil }
    end

    def is_state?(state)
      transitions.keys.include?(state.to_s)
    end

    def is_terminator?(state)
      terminators.include?(state.to_s)
    end

    def is_transitioner?(state)
      transitioners.include?(state.to_s)
    end

    private

      attr_reader :transitions

      def make_states(values)
        values = [values.to_s] unless values.respond_to?(:map)
        values = values.map(&:to_s)
        values.each { |value| transitions[value] ||= nil } unless transitions.frozen?
        values
      end
  end
end
