# frozen_string_literal: true

module StateJacket
  # Matrix defines a directed graph of states and their allowed transitions.
  #
  # Once locked, the matrix governs what state transitions are permitted.
  # Matrix provides methods to query and validate transitions against the defined rules.
  #
  class Matrix
    include MonitorMixin

    class Error < StandardError; end

    class << self
      # Creates a new Matrix from a hash representation.
      #
      # Alias: from_h
      #
      # @rbs hash: Hash[Symbol | String, Object]
      # @rbs return: Matrix
      def from_hash(hash)
        matrix = new

        rules = hash[:rules] || hash["rules"]
        raise Error, "Hash must contain a 'rules' key" unless rules

        rules.each { |from, to| matrix.add from => to }
        locked = hash[:locked] || hash["locked"]
        matrix.lock if locked

        matrix
      end

      alias_method :from_h, :from_hash
    end

    # @rbs @rules: Hash[String, Array[String | nil] | nil]
    # @rbs @locked: bool
    # @rbs @cached_states: Array[String]?
    # @rbs @cached_terminals: Array[String]?
    # @rbs @cached_transitioners: Array[String]?
    # @rbs @cached_transition_helpers: Hash[Symbol, Hash[String, String]]?

    # @rbs @rules: Hash[String, Array[String | nil] | nil] -- Mapping of state names to their allowed target states

    # standard:disable Layout/LeadingCommentSpace
    attr_reader :cached_states #: Array[String]? -- Cached states (only available when locked)
    attr_reader :cached_terminals #: Array[String]? -- Cached terminal states (only available when locked)
    attr_reader :cached_transitioners #: Array[String]? -- Cached transitioner states (only available when locked)
    attr_reader :cached_transitions #: Hash[Symbol, Hash[String, String]]? -- Cached individual transitions (only available when locked)
    # standard:enable Layout/LeadingCommentSpace

    # --------------------------------------------------------------------------
    # Core Initialization and State Methods
    # --------------------------------------------------------------------------

    # Initializes a new Matrix instance.
    # @rbs return: void
    def initialize
      super
      @rules = {}
      @locked = false
      @cached_states = nil
      @cached_terminals = nil
      @cached_transitioners = nil
      @cached_transition_helpers = nil
    end

    # Returns an array of all unique state names.
    #
    # @rbs return: Array[String]
    def states
      return @cached_states if locked? && @cached_states
      synchronize { @rules.keys.dup.freeze }
    end

    # Returns an array of state names that can transition to other states.
    #
    # @rbs return: Array[String]
    def transitioners
      return @cached_transitioners if locked? && @cached_transitioners
      synchronize { @rules.keys.select { |state| !@rules[state].nil? }.freeze }
    end

    # Returns an array of state names that are terminal (don't transition to other states).
    #
    # @rbs return: Array[String]
    def terminals
      return @cached_terminals if locked? && @cached_terminals
      synchronize { @rules.keys.select { |state| @rules[state].nil? }.freeze }
    end

    # Returns a deep frozen copy of the rules mapping.
    # This provides thread-safe, immutable access to the current rule definitions.
    #
    # @rbs return: Hash[String, Array[String | nil] | nil]
    def rules
      synchronize do
        @rules.transform_values { |v| v.nil? ? nil : v.dup.freeze }.freeze
      end
    end

    # --------------------------------------------------------------------------
    # Rule Definition and State Manipulation Methods
    # --------------------------------------------------------------------------

    # Adds a new rule or state to the matrix.
    #
    # If `rule` is not a Hash, it's treated as a single state name and added as a terminal state.
    # If `rule` is a Hash, it must define a single `from => to` mapping.
    #   - `from`: Can be a single state (String/Symbol) or an array of states.
    #   - `to`: Can be a single target state (String/Symbol), an array of target states,
    #           or `nil` (to define `from` state(s) as terminal).
    #
    # All state names are normalized to strings.
    # Target states specified in `to` are automatically added to the matrix as
    # terminal states if they don't already exist.
    #
    # @raise [Error] if the matrix is locked.
    # @raise [Error] if `rule` (as Hash) is empty, has multiple key-value pairs, or its key (after normalization) is missing, empty, or contains a nil element.
    # @rbs rule: String | Symbol | Hash[String | Symbol | Array[String | Symbol], String | Symbol | Array[String | Symbol] | nil]
    # @rbs return: self
    def add(rule)
      synchronize do
        raise Error, "additions not permitted when locked" if @locked
        return @rules[rule.to_s] = nil unless rule.is_a?(Hash)

        raise Error, "rule cannot be empty" if rule && rule.empty?
        raise Error, "rule must contain exactly one key-value pair" unless rule.one?

        from, to = rule.first
        from = normalize(from)
        to = normalize(to)

        raise Error, "missing transition key" if from.nil? || from.empty?
        raise Error, "nil transition key" if from.any? { it.nil? }

        from.each do |origin|
          case [@rules[origin], to]
          in nil, nil then @rules[origin] = nil
          in nil, Array then @rules[origin] = to
          in Array, Array then @rules[origin].concat(to).uniq!
          in Array, nil then @rules[origin] = nil
          end
        end

        to&.each do |destination|
          @rules[destination] = nil unless @rules.key?(destination)
        end
      end

      self
    end

    # --------------------------------------------------------------------------
    # System Control Methods
    # --------------------------------------------------------------------------

    # Locks the matrix, preventing any further changes.
    # This also freezes the internal transition structures to ensure immutability.
    #
    # @rbs return: self
    def lock
      synchronize do
        return self if @locked

        @rules.values.each { it&.freeze }
        @rules.freeze

        @cached_states = @rules.keys.freeze
        @cached_terminals = @rules.keys.select { |state| @rules[state].nil? }.freeze
        @cached_transitioners = @rules.keys.select { |state| !@rules[state].nil? }.freeze
        @cached_transition_helpers = build_transition_helpers.freeze

        @locked = true
      end

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

    # Returns a comprehensive hash representation of the state matrix.
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
        rules: rules,
        transitions: transitions
      }.freeze
    end

    alias_method :to_h, :to_hash

    # --------------------------------------------------------------------------
    # Transition Lookup Methods
    # --------------------------------------------------------------------------

    # Returns a transition hash for the given transition key.
    # Transition keys follow the pattern :from_to_destination (e.g., :booted_to_started).
    # This provides a convenient way to reference specific transitions when setting up machines.
    # When the matrix is unlocked, it builds the transition cache on demand and returns frozen results.
    # When locked, it returns from the cached transitions for better performance.
    #
    # @raise [Error] if the transition doesn't exist.
    # @rbs key: Symbol | String
    # @rbs return: Hash[String, String]
    def [](key)
      transitions = locked? ? @cached_transition_helpers : build_transition_helpers
      transition = transitions[key.to_sym]

      raise Error, "transition '#{key}' not found. Available transitions: #{transitions.keys.inspect}" unless transition

      locked? ? transition : transition.freeze
    end

    # Returns an array of all available transition keys.
    # Transition keys follow the pattern :from_to_destination (e.g., :booted_to_started).
    # When the matrix is unlocked, it builds the keys on demand.
    # When locked, it returns from the cached transitions for better performance.
    #
    # @rbs return: Array[Symbol]
    def transition_keys
      locked? ? @cached_transition_helpers.keys : build_transition_helpers.keys
    end

    # Returns a frozen hash of all transitions.
    # When the matrix is unlocked, it builds the transitions on demand.
    # When locked, it returns the cached transitions.
    #
    # @rbs return: Hash[Symbol, Hash[String, String]]
    def transitions
      locked? ? @cached_transition_helpers : build_transition_helpers.freeze
    end

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
    # @raise [Error] if `rule` is empty or has multiple key-value pairs.
    # @rbs rule: Hash[String | Symbol, String | Symbol]
    # @rbs return: bool
    def allows?(rule)
      raise Error, "transition cannot be empty" if rule&.empty?
      raise Error, "transition must contain exactly one key-value pair" unless rule.one?

      from, to = rule.first
      synchronize do
        destinations = @rules[from.to_s]
        destinations&.include? to.to_s
      end
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
      raise Error, "rule cannot be empty" if rule&.empty?
      raise Error, "rule must contain exactly one key-value pair" unless rule.one?

      from, to = rule.first
      from = normalize(from)
      to = normalize(to)

      return false if from.nil? || from.empty?
      return false if to&.empty?

      synchronize do
        from.any? do |key|
          next unless @rules.key?(key)
          to == @rules[key] || to&.any? { @rules[key]&.include? it }
        end
      end
    end

    # Checks if a given rule strictly matches a defined transition rule in the matrix.
    # The `rule` hash must represent a single `from => to` mapping.
    # The `from` state(s) and `to` state(s) are normalized.
    # The rule matches if any of the normalized `from` states are defined to transition
    # to the exact set of normalized `to` states.
    #
    # @raise [ArgumentError] if `rule` is empty or has multiple key-value pairs.
    # @rbs rule: Hash[String | Symbol | Array[String | Symbol], String | Symbol | Array[String | Symbol] | nil]
    # @rbs return: bool
    def match?(rule)
      raise Error, "rule cannot be empty" if rule&.empty?
      raise Error, "rule must contain exactly one key-value pair" unless rule.one?

      from, to = rule.first
      from = normalize(from)
      to = normalize(to)

      synchronize { from.any? { @rules.key?(it) && @rules[it] == to } }
    end

    # Checks if the transition rules are currently locked.
    # Locked rules cannot have new states or transitions added.
    # Reading @locked is safe without synchronization since:
    # - Boolean reads are atomic in Ruby
    # - @locked is only modified within synchronized blocks
    #
    # @rbs return: bool
    def locked?
      !!@locked
    end

    # Checks if a given state name exists within the matrix.
    #
    # @rbs state: String | Symbol
    # @rbs return: bool
    def include?(state)
      synchronize { @rules.key? state.to_s }
    end

    # Checks if a given state name is a terminal state.
    # A terminal state has no outgoing transitions.
    #
    # @rbs state: String | Symbol
    # @rbs return: bool
    def terminal?(state)
      synchronize do
        return false unless @rules.key?(state.to_s)
        return @cached_terminals.include?(state.to_s) if @locked
        @rules[state.to_s].nil?
      end
    end

    # Checks if a given state name is a transitioner state.
    # A transitioner state has one or more defined outgoing transitions.
    #
    # @rbs state: String | Symbol
    # @rbs return: bool
    def transitioner?(state)
      synchronize do
        return false unless @rules.key?(state.to_s)
        return @cached_transitioners.include?(state.to_s) if @locked
        !!@rules[state.to_s]
      end
    end

    private

    # Builds a cache of transition helpers.
    # Keys follow the pattern :from_to_destination (e.g., :booted_to_started).
    #
    # @rbs return: Hash[Symbol, Hash[String, String]]
    def build_transition_helpers
      cache = {}

      @rules.each do |from_state, destinations|
        next if destinations.nil? # Skip terminal states

        destinations.each do |to_state|
          key = :"#{from_state}_to_#{to_state}"
          cache[key] = {from_state => to_state}.freeze
        end
      end

      cache
    end

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
