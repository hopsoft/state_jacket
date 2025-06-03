# frozen_string_literal: true

module StateJacket
  # Lightweight TransitionResult using Struct for optimal performance
  # Supports Ruby 3+ pattern matching for elegant transition handling:
  #   result = machine.trigger(:submit)
  #   case result
  #   in [true, from_state, to_state, event]
  #     celebrate_publication(from_state, to_state, event)
  #   in { success?: false, from: state }
  #     handle_failure(state)
  #   end
  TransitionResult = Struct.new(:success, :from_state, :to_state, :event) do
    # Returns true if the transition was successful
    # @rbs return: bool
    def success?
      success
    end

    # Returns true if the transition failed
    # @rbs return: bool
    def failed?
      !success
    end

    # Support for hash-style pattern matching with focused, semantic keys
    # Enables: case result; in { success?: true, from: "draft", to: "published" }; end
    # @rbs keys: Array[Symbol] -- The keys to extract
    # @rbs return: Hash[Symbol, bool | String | String?]
    def deconstruct_keys(keys)
      {
        success?: success,
        failed?: !success,
        from: from_state,
        to: to_state,
        event: event,
        changed?: success && from_state != to_state
      }.slice(*keys)
    end
  end
end
