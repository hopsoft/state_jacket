# frozen_string_literal: true

require_relative "state_jacket/version"
require_relative "state_jacket/state_transition_system"
require_relative "state_jacket/state_machine"

# StateJacket provides an intuitive approach to building complex state machines
# by isolating the concerns of the state transition system & state machine.
#
# The library consists of two main components:
# - StateTransitionSystem: Defines valid states and allowed transitions
# - StateMachine: Manages current state and handles event-driven transitions
#
# @rbs!
#   # Semantic version string for the StateJacket gem
#   VERSION: String
module StateJacket
end
