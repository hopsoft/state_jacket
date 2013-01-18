# StateJacket

## An Intuitive [State Transition System](http://en.wikipedia.org/wiki/State_transition_system)

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

## Next Steps

Lets model something a bit more complex.

#### Define states &amp; transitions for a phone call.

![Phone Call](https://raw.github.com/hopsoft/state_jacket/master/doc/phone-call.png)

```ruby
require "state_jacket"

states = StateJacket::Catalog.new
states.add :idle => [:dialing]
states.add :dialing => [:idle, :connecting]
states.add :connecting => [:idle, :busy, :connected]
states.add :busy => [:idle]
states.add :connected => [:idle]
states.lock

states.transitioners # => [:idle, :dialing, :connecting, :busy, :connected]
states.terminators # => []

states.can_transition? :idle => :dialing # => true
states.can_transition? :dialing => [:idle, :connecting] # => true
states.can_transition? :connecting => [:idle, :busy, :connected] # => true
states.can_transition? :busy => :idle # => true
states.can_transition? :connected => :idle # => true
states.can_transition? :idle => [:dialing, :connected] # => false
```

