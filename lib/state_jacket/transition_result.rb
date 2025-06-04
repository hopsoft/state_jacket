# frozen_string_literal: true

module StateJacket
  TransitionResult = Struct.new(:event, :from, :to, :status, :error) do
    def successful?
      status == :ok
    end

    def deconstruct_keys(keys)
      return to_h.slice(*keys) if keys
      to_h
    end
  end
end
