# StateJacket

## Intuitively define state machine like states and transitions.

[State machines](http://en.wikipedia.org/wiki/Finite-state_machine) are awesome
but can be pretty daunting as a system grows.
Keeping states, transitions, & events straight can be tricky.

StateJacket simplifies things by isolating the management of states & transitions.
Events are left out, making it much easier to reason about what states exist
and how they transition to other states.

## Quick Start

#### Install

```
$ gem install state_jacket
```

#### Define states for a simple [turnstyle](http://en.wikipedia.org/wiki/Finite-state_machine#Example:_a_turnstile).

![Turnstyle](https://raw.github.com/hopsoft/state_jacket/master/doc/turnstyle.png)

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

