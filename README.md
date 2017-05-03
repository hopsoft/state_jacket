[![Lines of Code](http://img.shields.io/badge/lines_of_code-130-brightgreen.svg?style=flat)](http://blog.codinghorror.com/the-best-code-is-no-code-at-all/)
[![Code Status](http://img.shields.io/codeclimate/github/hopsoft/state_jacket.svg?style=flat)](https://codeclimate.com/github/hopsoft/state_jacket)
[![Dependency Status](http://img.shields.io/gemnasium/hopsoft/state_jacket.svg?style=flat)](https://gemnasium.com/hopsoft/state_jacket)
[![Build Status](http://img.shields.io/travis/hopsoft/state_jacket.svg?style=flat)](https://travis-ci.org/hopsoft/state_jacket)
[![Coverage Status](https://img.shields.io/coveralls/hopsoft/state_jacket.svg?style=flat)](https://coveralls.io/r/hopsoft/state_jacket?branch=master)
[![Downloads](http://img.shields.io/gem/dt/state_jacket.svg?style=flat)](http://rubygems.org/gems/state_jacket)

# StateJacket

## An Intuitive [State Transition System](http://en.wikipedia.org/wiki/State_transition_system) & [State Machine](https://en.wikipedia.org/wiki/Finite-state_machine)

StateJacket isolates the concerns of the state transition system & state machine.

## Install

```sh
gem install state_jacket
```

## Example

Let's define states & transitions (i.e. the state transition system) & a state machine for a [turnstyle](http://en.wikipedia.org/wiki/Finite-state_machine#Example:_a_turnstile).

![Turnstyle](https://raw.github.com/hopsoft/state_jacket/master/doc/turnstyle.png)

### State Transition System

```ruby
system = StateJacket::StateTransitionSystem.new
system.add :opened => [:closed, :errored]
system.add :closed => [:opened, :errored]
system.lock # prevent further changes

system.to_h.inspect  # => {"opened"=>["closed", "errored"], "closed"=>["opened", "errored"], "errored"=>nil}
system.transitioners # => ["opened", "closed"]
system.terminators   # => ["errored"]

system.can_transition? :opened => :closed  # => true
system.can_transition? :closed => :opened  # => true
system.can_transition? :errored => :opened # => false
system.can_transition? :errored => :closed # => false
```

### State Machine

Define the events that trigger transitions defined by the state transition system (i.e. the state machine).

```ruby
machine = StateJacket::StateMachine.new(system, state: "closed")
machine.on :open, :closed => :opened
machine.on :close, :opened => :closed
machine.lock # prevent further changes

machine.to_h.inspect # => {"open"=>[{"closed"=>"opened"}], "close"=>[{"opened"=>"closed"}]}
machine.events       # => ["open", "close"]

machine.state            # => "closed"
machine.is_event? :open  # => true
machine.is_event? :close # => true
machine.is_event? :other # => false

machine.can_trigger? :open # => true
machine.can_trigger? :close # => false

machine.state         # => "closed"
machine.trigger :open # => "opened"
machine.state         # => "opened"

# you can also pass a block when triggering events
machine.trigger :close do |from_state, to_state|
  # custom logic can be placed here
  from_state # => "opened"
  to_state   # => "closed"
end

machine.state # => "closed"

# this is a noop because can_trigger?(:close) is false
machine.trigger :close # => nil

machine.state # => "closed"

begin
  machine.trigger :open do |from_state, to_state|
    raise # the transition isn't performed if an error occurs in the block
  end
rescue
end

machine.state # => "closed"
```
