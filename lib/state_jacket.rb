require_relative "./state_jacket/version"

class StateJacket
  def initialize
    @hash = {}
  end

  def to_h
    @hash
  end

  def add(state)
    if state.is_a?(Hash)
      from = state.keys.first.to_s
      @hash[from] = states(state.values.first)
    else
      @hash[state.to_s] = nil
    end
  end

  def lock
    @hash.freeze
    @hash.values.each { |value| value.freeze unless value.nil? }
  end

  def can_transition?(from_to)
    from = from_to.keys.first.to_s
    to = states(from_to.values.first)
    transitions =  @hash[from] || []
    (to & transitions).length == to.length
  end

  def transitioners
    @hash.keys.select { |state| @hash[state] != nil }
  end

  def terminators
    @hash.keys.select { |state| @hash[state] == nil }
  end

  def is_state?(state)
    @hash.keys.include?(state.to_s)
  end

  def is_terminator?(state)
    terminators.include?(state.to_s)
  end

  def is_transitioner?(state)
    transitioners.include?(state.to_s)
  end

  private

    def states(values)
      values = [values.to_s] unless values.respond_to?(:map)
      values = values.map(&:to_s)
      values.each { |value| @hash[value] ||= nil } unless @hash.frozen?
      values
    end
end
