require "delegate"

module StateJacket

  # A simple class that allows users to intuitively define states and transitions.
  class Catalog < SimpleDelegator
    def initialize
      @inner_hash = {}
      super inner_hash
    end

    def add(state)
      if state.is_a?(Hash)
        self[state.keys.first.to_s] = state.values.first.map(&:to_s)
      else
        self[state.to_s] = nil
      end
    end

    def can_transition?(from_to)
      from = from_to.keys.first.to_s
      to = from_to.values.first
      to = [to] unless to.is_a?(Array)
      to = to.map(&:to_s)
      transitions = self[from] || []
      (to & transitions).length == to.length
    end

    def transitioners
      keys.select do |state|
        self[state] != nil
      end
    end

    def transitioner?(state)
      transitioners.include?(state.to_s)
    end

    def terminators
      keys.select do |state|
        self[state] == nil
      end
    end

    def terminator?(state)
      terminators.include?(state.to_s)
    end

    def lock
      values.flatten.each do |value|
        next if value.nil?
        if !keys.include?(value)
          raise "Invalid StateJacket::Catalog! [#{value}] is not a first class state."
        end
      end
      inner_hash.freeze
    end

    def supports_state?(state)
      keys.include?(state.to_s)
    end

    protected

    attr_reader :inner_hash

  end

end


