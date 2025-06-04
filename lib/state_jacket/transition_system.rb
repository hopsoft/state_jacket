# frozen_string_literal: true

module StateJacket
  # TransitionSystem defines a directed graph of states and their allowed transitions.
  #
  # @example Creating from a hash representation
  #   hash = existing_system.to_hash
  #   system = TransitionSystem.from_hash(hash)
  #
  # A "rule" in this context defines what transitions are allowed from one or more states.
  # Rules can be defined in several ways:
  #
  # 1. Adding a terminal state (a state with no outgoing transitions):
  #    ```ruby
  #    system.add :completed
  #    ```
  #
  # 2. Adding a transition from one state to another:
  #    ```ruby
  #    system.add pending: :approved
  #    ```
  #
  # 3. Adding multiple possible transitions from a state:
  #    ```ruby
  #    system.add pending: [:approved, :rejected]
  #    ```
  #
  # 4. Adding the same transition for multiple source states:
  #    ```ruby
  #    system.add [:reviewing, :pending] => :approved
  #    ```
  #
  # 5. Making an existing transitioner state into a terminal state:
  #    ```ruby
  #    system.add processing: nil
  #    ```
  #
  # Once defined and locked, the system governs what state transitions are permitted.
  # TransitionSystem provides methods to query and validate transitions against the defined rules.
  #
  class TransitionSystem
    class << self
      # Creates a new TransitionSystem from a hash representation.
      #
      # The hash should include a 'rules' key mapping state names to their allowed
      # target states. The system will be locked if the 'locked' key is true.
      #
      # Alias: from_h
      #
      # @rbs hash: Hash[Symbol | String, Object]
      # @rbs return: TransitionSystem
      def from_hash(hash)
        system = new

        rules = hash[:rules] || hash["rules"]
        raise ArgumentError, "Hash must contain a 'rules' key" unless rules

        rules.each { |from, to| system.add from => to }
        locked = hash[:locked] || hash["locked"]
        system.lock if locked

        system
      end

      alias_method :from_h, :from_hash
    end

    # @rbs @rules: Hash[String, Array[String | nil] | nil]
    # @rbs @locked: bool
    # @rbs @cached_terminals: Array[String]?
    # @rbs @cached_transitioners: Array[String]?

    # standard:disable Layout/LeadingCommentSpace
    attr_reader :rules #: Hash[String, Array[String | nil] | nil] -- Mapping of state names to their allowed target states
    # standard:enable Layout/LeadingCommentSpace

    # --------------------------------------------------------------------------
    # Core Initialization and State Methods
    # --------------------------------------------------------------------------

    # Initializes a new TransitionSystem instance.
    # @rbs return: void
    def initialize
      @rules = {}
      @locked = false
      @cached_terminals = nil
      @cached_transitioners = nil
    end

    # Returns an array of all unique state names.
    #
    # @rbs return: Array[String]
    def states
      rules.keys
    end

    # Returns an array of state names that can transition to other states.
    #
    # @rbs return: Array[String]
    def transitioners
      return @cached_transitioners if locked? && @cached_transitioners
      rules.keys.select { |state| !rules[state].nil? }
    end

    # Returns an array of state names that are terminal (don't transition to other states).
    #
    # @rbs return: Array[String]
    def terminals
      return @cached_terminals if locked? && @cached_terminals
      rules.keys.select { |state| rules[state].nil? }
    end

    # --------------------------------------------------------------------------
    # Rule Definition and State Manipulation Methods
    # --------------------------------------------------------------------------

    # Adds a new rule or state to the system.
    #
    # If `rule` is not a Hash, it's treated as a single state name and added as a terminal state.
    # If `rule` is a Hash, it must define a single `from => to` mapping.
    #   - `from`: Can be a single state (String/Symbol) or an array of states.
    #   - `to`: Can be a single target state (String/Symbol), an array of target states,
    #           or `nil` (to define `from` state(s) as terminal).
    #
    # All state names are normalized to strings.
    # Target states specified in `to` are automatically added to the system as
    # terminal states if they don't already exist.
    #
    # @raise [ArgumentError] if the system is locked.
    # @raise [ArgumentError] if `rule` (as Hash) is empty, has multiple key-value pairs, or its key (after normalization) is missing, empty, or contains a nil element.
    # @rbs rule: String | Symbol | Hash[String | Symbol | Array[String | Symbol], String | Symbol | Array[String | Symbol] | nil]
    # @rbs return: self
    def add(rule)
      raise ArgumentError, "additions not permitted when locked" if locked?
      return rules[rule.to_s] = nil unless rule.is_a?(Hash)

      raise ArgumentError, "rule cannot be empty" if rule && rule.empty?
      raise ArgumentError, "rule must contain exactly one key-value pair" unless rule.one?

      from, to = rule.first
      from = normalize(from)
      to = normalize(to)

      raise ArgumentError, "missing transition key" if from.nil? || from.empty?
      raise ArgumentError, "nil transition key" if from.any? { it.nil? }

      from.each do |origin|
        case [rules[origin], to]
        in nil, nil then rules[origin] = nil
        in nil, Array then rules[origin] = to
        in Array, Array then rules[origin].concat(to).uniq!
        in Array, nil then rules[origin] = nil
        end
      end

      to&.each do |destination|
        rules[destination] = nil unless rules.key?(destination)
      end

      self
    end

    # --------------------------------------------------------------------------
    # System Control Methods
    # --------------------------------------------------------------------------

    # Locks the system, preventing any further additions.
    # This also freezes the internal transition structures to ensure immutability.
    #
    # @rbs return: self
    def lock
      return self if locked?

      rules.values.each { it&.freeze }
      rules.freeze

      @cached_terminals = rules.keys.select { |state| rules[state].nil? }.freeze
      @cached_transitioners = rules.keys.select { |state| !rules[state].nil? }.freeze

      @locked = true
      self
    end

    # --------------------------------------------------------------------------
    # Serialization Methods
    # --------------------------------------------------------------------------

    # Supports pattern matching by allowing the rules to be deconstructed into a hash.
    # If `keys` is provided, only those keys will be included in the resulting hash.
    # If `keys` is `nil` or empty, a full hash representation (same as `to_hash`) is returned.
    #
    # @rbs keys: Array[Symbol]?
    # @rbs return: Hash[Symbol, bool | Array[String] | Hash[String, Array[String | nil] | nil]]
    def deconstruct_keys(keys)
      keys&.any? ? to_hash.slice(*keys) : to_hash
    end

    # Returns a comprehensive hash representation of the transition system.
    # This include lock status, all states, transitioner states, terminal states, and the complete rule map.
    #
    # Alias: to_h
    #
    # @rbs return: { locked: bool, states: Array[String], transitioners: Array[String], terminals: Array[String], rules: Hash[String, Array[String | nil] | nil] }
    def to_hash
      {
        locked: locked?,
        states: states,
        transitioners: transitioners,
        terminals: terminals,
        rules: rules.dup
      }
    end

    alias_method :to_h, :to_hash

    # --------------------------------------------------------------------------
    # Query and Validation Methods
    # --------------------------------------------------------------------------

    # Checks if a specific `from` state can transition directly to a specific `to` state.
    # The `rule` hash must represent a single `from => to` mapping with exactly one key-value pair.
    # This is a "loose" validation, meaning it returns true if this specific transition
    # is *one of* the allowed transitions for the `from` state, even if the `from` state
    # can also transition to other states. Unlike `match?`, this does not require exact
    # rule matching - it only checks if the individual transition is allowed.
    #
    # @raise [ArgumentError] if `rule` is empty or has multiple key-value pairs.
    # @rbs rule: Hash[String | Symbol, String | Symbol]
    # @rbs return: bool
    def allows?(rule)
      raise ArgumentError, "transition cannot be empty" if rule&.empty?
      raise ArgumentError, "transition must contain exactly one key-value pair" unless rule.one?

      from, to = rule.first
      destinations = rules[from.to_s]
      destinations&.include? to.to_s
    end

    # Checks if any of the specified `from` states can transition to any of the specified `to` states.
    # The `rule` hash must represent a single `from => to` mapping.
    # The `from` state(s) and `to` state(s) are normalized.
    # This is a "permissive" validation, meaning it returns true if there's any overlap
    # between the specified transitions and the defined rules. Unlike `match?`, this does not
    # require exact rule matching - it checks for any overlap between specified and allowed transitions.
    #
    # @raise [ArgumentError] if `rule` is empty or has multiple key-value pairs.
    # @rbs rule: Hash[String | Symbol | Array[String | Symbol], String | Symbol | Array[String | Symbol] | nil]
    # @rbs return: bool
    def overlaps?(rule)
      raise ArgumentError, "rule cannot be empty" if rule&.empty?
      raise ArgumentError, "rule must contain exactly one key-value pair" unless rule.one?

      from, to = rule.first
      from = normalize(from)
      to = normalize(to)

      return false if from.nil? || from.empty?
      return false if to&.empty?

      from.any? do |key|
        next unless rules.key?(key)
        to == rules[key] || to&.any? { rules[key]&.include? it }
      end
    end

    # Checks if a given rule strictly matches a defined transition rule in the system.
    # The `rule` hash must represent a single `from => to` mapping.
    # The `from` state(s) and `to` state(s) are normalized.
    # The rule matches if any of the normalized `from` states are defined to transition
    # to the exact set of normalized `to` states.
    #
    # @raise [ArgumentError] if `rule` is empty or has multiple key-value pairs.
    # @rbs rule: Hash[String | Symbol | Array[String | Symbol], String | Symbol | Array[String | Symbol] | nil]
    # @rbs return: bool
    def match?(rule)
      raise ArgumentError, "rule cannot be empty" if rule&.empty?
      raise ArgumentError, "rule must contain exactly one key-value pair" unless rule.one?

      from, to = rule.first
      from = normalize(from)
      to = normalize(to)

      from.any? { rules.key?(it) && rules[it] == to }
    end

    # Checks if the transition rules are currently locked.
    # Locked rules cannot have new states or transitions added.
    #
    # @rbs return: bool
    def locked?
      !!@locked
    end

    # Checks if a given state name exists within the system.
    #
    # @rbs state: String | Symbol
    # @rbs return: bool
    def include?(state)
      rules.key? state.to_s
    end

    # Checks if a given state name is a terminal state.
    # A terminal state has no outgoing transitions.
    #
    # @rbs state: String | Symbol
    # @rbs return: bool
    def terminal?(state)
      return false unless include?(state)
      return @cached_terminals.include?(state.to_s) if locked?
      rules[state.to_s].nil?
    end

    # Checks if a given state name is a transitioner state.
    # A transitioner state has one or more defined outgoing transitions.
    #
    # @rbs state: String | Symbol
    # @rbs return: bool
    def transitioner?(state)
      return false unless include?(state)
      return @cached_transitioners.include?(state.to_s) if locked?
      !!rules[state.to_s]
    end

    private

    # Normalizes state names.
    # - If `states` is `nil`, returns `nil`.
    # - If `states` is an `Enumerable` (e.g., Array), it maps each element to its
    #   string representation (or `nil` if the element is `nil`).
    # - Otherwise (e.g., a single String or Symbol), it returns an array containing
    #   the string representation of `states`.
    #
    # @rbs states: String | Symbol | Enumerable[String | Symbol] | nil
    # @rbs return: Array[String] | nil
    def normalize(states)
      case states
      in nil then nil
      in Enumerable then states.map { it&.to_s }
      else [states.to_s]
      end
    end
  end
end
