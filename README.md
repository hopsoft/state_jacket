# StateJacket

### Intuitively define state machine like states and transitions.

StateJacket provides an intuitive DSL for defining states and their transitions.

## Quick Start

Install

```
$ gem install state_jacket
```

Define states for a simple [turnstyle](http://en.wikipedia.org/wiki/Finite-state_machine#Example:_a_turnstile).

```ruby
require "state_jacket"

states = StateJacket::Catalog.new
states.add :open => [:closed, :error]
states.add :closed => [:open, :error]
states.add :error
states.lock

states.transitioners # => [:open, :closed]
states.terminators # => [:error]

states.can_transition? :open => :closed # => true
states.can_transition? :closed => :open # => true
states.can_transition? :error => :open # => false
states.can_transition? :error => :closed # => false
```

