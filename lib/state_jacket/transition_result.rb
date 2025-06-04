# frozen_string_literal: true

module StateJacket
  # TransitionResult represents the outcome of a state transition.
  #
  # A transition result includes information about:
  # - The event that triggered the transition
  # - The original and target states
  # - The transition status (:ok or :error)
  # - Any error that occurred during transition
  #
  # @rbs class TransitionResult < Struct[String, String, String, Symbol, StandardError?]
  # @rbs attr event: String -- The name of the triggered event
  # @rbs attr from: String -- The original state before transition
  # @rbs attr to: String -- The target state after transition
  # @rbs attr status: Symbol -- The status of the transition (:ok or :error)
  # @rbs attr error: StandardError? -- Any error that occurred (nil if successful)
  TransitionResult = Struct.new(:event, :from, :to, :status, :error) do
    # Returns true if the transition was successful.
    #
    # @rbs return: bool
    def successful?
      status == :ok
    end

    # Supports pattern matching by allowing the result to be deconstructed into a hash.
    # If keys is provided, only those keys will be included in the resulting hash.
    #
    # @rbs keys: Array[Symbol]?
    # @rbs return: Hash[Symbol, String | Symbol | StandardError?]
    def deconstruct_keys(keys)
      return to_h.slice(*keys) if keys
      to_h
    end
  end
end
