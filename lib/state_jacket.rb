# frozen_string_literal: true

require_relative "state_jacket/version"
require_relative "state_jacket/state_transition_system"
require_relative "state_jacket/state_machine"
require_relative "state_jacket/transition_result"

# StateJacket provides an intuitive approach to building complex state machines
# through a clean two-layer architecture that separates concerns.
#
# THE TWO-LAYER ARCHITECTURE:
#
# Layer 1 - StateTransitionSystem (The Foundation):
#   Defines the "business rules" - what states exist and which transitions are valid.
#   Think of this as your state machine's blueprint or contract.
#
# Layer 2 - StateMachine (The Behavior Engine):
#   Manages current state and handles event-driven transitions.
#   This is where your application logic and event handling lives.
#
# DESIGN PHILOSOPHY:
#   - Explicit over implicit: Business logic belongs in your domain objects
#   - Separation of concerns: State rules and event logic are distinct responsibilities
#   - Clean architecture: Test business rules independently from event handling
#   - Thread safety: Immutable after locking for safe concurrent access
#
# ELEGANT SYNTAX:
#   machine.on :event, single_from: :to
#   machine.on :event, {:from1 => :to, :from2 => :to}
#   machine.on :event, [:from1, :from2] => :to # Array syntax
#
# EXAMPLE USAGE:
#   # Define the business rules
#   system = StateTransitionSystem.new
#   system.add(draft: [:published, :archived])
#   system.add(:published)
#   system.add(:archived)
#   system.lock
#
#   # Create and configure the state machine
#   machine = StateMachine.new(system, state: :draft)
#   machine.on :publish, draft: :published
#   machine.on :archive, [:draft, :published] => :archived
#   machine.lock
#
#   # Use the state machine
#   result = machine.trigger(:publish)
#   case result
#   in success?: true, from: "draft", to: "published"
#     puts "Successfully published!"
#   in success?: false
#     puts "Publication failed"
#   end
module StateJacket
  # Idiomatic pattern matching support using procs and case equality
  # These patterns work naturally with case/in expressions and guard clauses
  module Patterns
    # Simple pattern matchers using case equality
    Success = ->(result) { result.is_a?(TransitionResult) && result.success? }
    Failure = ->(result) { result.is_a?(TransitionResult) && result.failed? }

    # State change pattern (successful transition between different states)
    StateChange = ->(result) {
      result.is_a?(TransitionResult) &&
        result.success? &&
        result.from_state != result.to_state
    }

    # Semantic transition patterns
    Activation = ->(result) {
      result.is_a?(TransitionResult) &&
        result.success? &&
        %w[active activated].include?(result.to_state)
    }

    Completion = ->(result) {
      result.is_a?(TransitionResult) &&
        result.success? &&
        %w[completed finished done].include?(result.to_state)
    }

    # Parameterized patterns using currying
    # Usage: case result; in FromState[:pending]; end
    FromState = ->(state) do
      ->(result) { result.is_a?(TransitionResult) && result.from_state == state.to_s }
    end

    ToState = ->(state) do
      ->(result) { result.is_a?(TransitionResult) && result.to_state == state.to_s }
    end

    WithEvent = ->(event) do
      ->(result) { result.is_a?(TransitionResult) && result.event == event.to_s }
    end
  end
end
