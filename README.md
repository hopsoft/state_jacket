[![Lines of Code](http://img.shields.io/badge/lines_of_code-60-brightgreen.svg?style=flat)](http://blog.codinghorror.com/the-best-code-is-no-code-at-all/)
[![Code Status](http://img.shields.io/codeclimate/github/hopsoft/state_jacket.svg?style=flat)](https://codeclimate.com/github/hopsoft/state_jacket)
[![Dependency Status](http://img.shields.io/gemnasium/hopsoft/state_jacket.svg?style=flat)](https://gemnasium.com/hopsoft/state_jacket)
[![Build Status](http://img.shields.io/travis/hopsoft/state_jacket.svg?style=flat)](https://travis-ci.org/hopsoft/state_jacket)
[![Coverage Status](https://img.shields.io/coveralls/hopsoft/state_jacket.svg?style=flat)](https://coveralls.io/r/hopsoft/state_jacket?branch=master)
[![Downloads](http://img.shields.io/gem/dt/state_jacket.svg?style=flat)](http://rubygems.org/gems/state_jacket)

# StateJacket

## An Intuitive [State Transition System](http://en.wikipedia.org/wiki/State_transition_system)

[State machines](http://en.wikipedia.org/wiki/Finite-state_machine) are awesome
but can be pretty daunting as a system grows.
Keeping states, transitions, & events straight can be tricky.
StateJacket simplifies things by isolating the management of states & transitions.
Events are left out, making it much easier to reason about what states exist
and how they transition to other states.

*The examples below are somewhat contrived, but should clearly illustrate usage.*

## The Basics

#### Install

```sh
gem install state_jacket
```

#### Define states &amp; transitions for a simple [turnstyle](http://en.wikipedia.org/wiki/Finite-state_machine#Example:_a_turnstile).

![Turnstyle](https://raw.github.com/hopsoft/state_jacket/master/doc/turnstyle.png)

```ruby
require "state_jacket"

states = StateJacket::Catalog.new
states.add :open => [:closed, :error]
states.add :closed => [:open, :error]
states.add :error
states.lock

states.inspect # => {:open=>[:closed, :error], :closed=>[:open, :error], :error=>nil}
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

## Deep Cuts

Lets add state awareness and behavior to another class.
We'll reuse the turnstyle states from the example from above.

```ruby
require "state_jacket"

class Turnstyle
  attr_reader :states, :current_state

  def initialize
    @states = StateJacket::Catalog.new
    @states.add :open => [:closed, :error]
    @states.add :closed => [:open, :error]
    @states.add :error
    @states.lock
    @current_state = :closed
  end

  def open
    if states.can_transition? current_state => :open
      @current_state = :open
    else
      raise "Can't transition from #{@current_state} to :open"
    end
  end

  def close
    if states.can_transition? current_state => :closed
      @current_state = :closed
    else
      raise "Can't transition from #{@current_state} to :closed"
    end
  end

  def break
    @current_state = :error
  end
end

# example usage
turnstyle = Turnstyle.new
turnstyle.current_state # => :closed
turnstyle.open
turnstyle.current_state # => :open
turnstyle.close
turnstyle.current_state # => :closed
turnstyle.close # => RuntimeError: Can't transition from closed to :closed
turnstyle.open
turnstyle.current_state # => :open
turnstyle.open # => RuntimeError: Can't transition from open to :open
turnstyle.break
turnstyle.open # => RuntimeError: Can't transition from error to :open
turnstyle.close # => RuntimeError: Can't transition from error to :closed
```

## Running the Tests

```
gem install state_jacket
gem unpack state_jacket
cd state_jacket-VERSION
rake
```
