require "delegate"

module StateJacket

  # A simple class that allows users to intuitively define states and transitions.
  class Catalog < SimpleDelegator
    def initialize
      super({})
    end

    def add(state)
      if state.is_a?(Hash)
        self[state.keys.first.to_sym] = state.values.first.map(&:to_sym)
      else
        self[state] = nil
      end
    end

    def can_transition?(from_to)
      from = from_to.keys.first.to_sym
      to = from_to.values.first
      to = [to] unless to.is_a?(Array)
      to = to.map(&:to_sym)
      transitions = self[from] || []
      (to & transitions).length == to.length
    end

    def transitioners
      keys.select do |state|
        self[state] != nil
      end
    end

    def terminators
      keys.select do |state|
        self[state] == nil
      end
    end

    def lock
      values.each do |value|
        next if value.nil?
        if (keys & value).length != value.length
          raise "Invalid StateCatalog! #{value} is not a first class state."
        end
      end
      freeze
    end
  end

end


