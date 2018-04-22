[![Build Status](https://travis-ci.org/Stex/petra.svg?branch=master)](https://travis-ci.org/Stex/petra)

# petra
<img src="https://drive.google.com/uc?id=1BKauBWbE66keL1gBBDfgSaRE0lL5x586&export=download" width="200" align="right" />

Petra is a proof-of-concept for **pe**rsisted **tra**nsactions in Ruby with (hopefully) full `ACI(D)` properties.

Please note that this was created during my master's thesis in 2016 and hasn't been extended a lot since then except for a few coding style fixes. I would write a lot of stuff differently today, but the main concept is still interesting enough.

It allows starting a transaction without committing it and resuming it at a later time, even in another process - given the used objects provide identifiers other than `object_id`.

It should work with every Ruby object and can be extended to work with web frameworks like Ruby-on-Rails as well (a POC of RoR integration can be found at [stex/petra-rails](https://github.com/stex/petra-rails)). 

Let's take a look at how `petra` is used:

```ruby
class SimpleUser
  attr_accessor :first_name, :last_name
  
  def name
    "#{first_name} #{last_name}"
  end
  
  # ... configuration, see below
end

user = SimpleUser.petra.new
user.first_name, user.last_name = 'John', 'Doe'

# Start a new transaction and start changing attributes
Petra.transaction(identifier: 'tr1') do
  user.first_name = 'Foo'
end

# No changes outside the transaction yet...
puts user.name #=> 'John Doe'

# Continue the same transaction
Petra.transaction(identifier: 'tr1') do
  puts user.name #=> 'Foo Doe'
  user.last_name = 'Bar'
end

# Still nothing...
puts user.name #=> 'John Doe'

# Commit the transaction
Petra.transaction(identifier: 'tr1') do
  puts user.name #=> 'Foo Bar'
  Petra.commit!
end

# The actual object is finally updated
puts user.name #=> 'Foo Bar'
```

We just used a simple Ruby object inside a transaction which was even split into multiple sections! 

<!-- START doctoc generated TOC please keep comment here to allow auto update -->
<!-- DON'T EDIT THIS SECTION, INSTEAD RE-RUN doctoc TO UPDATE -->
## TOC

- [Basic Usage](#basic-usage)
  - [Starting/Resuming a transaction](#startingresuming-a-transaction)
  - [Transactional Objects and their Configuration](#transactional-objects-and-their-configuration)
  - [Commit / Rollback / Reset / Retry](#commit--rollback--reset--retry)
- [Reacting to external changes](#reacting-to-external-changes)
  - [An attribute we previously read was changed externally](#an-attribute-we-previously-read-was-changed-externally)
  - [An attribute we changed in our transaction was also changed externally](#an-attribute-we-changed-in-our-transaction-was-also-changed-externally)
- [Full Configuration Options](#full-configuration-options)
- [Custom Proxy Classes](#custom-proxy-classes)
- [How it works](#how-it-works)

<!-- END doctoc generated TOC please keep comment here to allow auto update -->

## Basic Usage

### Starting/Resuming a transaction

Whenver you call `Petra.transaction`, a *transaction section* is started. If you pass in an identifier and a matching transaction already exists, it will be resumed instead.

```ruby
# Starting a new transaction with an auto-generated identifier
tr_id = Petra.transaction {}

# Resuming the transaction
Petra.transaction(identifier: tr_id) {}
```

### Transactional Objects and their Configuration

Although `petra` is seemingly able to use every Ruby object inside a transaction, it does not patch these objects in any way by e.g. overriding their getters and setters. Instead, a transparent proxy is used:

```
# Normal instance of SimpleUser
user = SimpleUser.new

# ObjectProxy, can now be used inside and outside of transactions
user = SimpleUser.petra.new # or: user = SimpleUser.new.petra
```

In its current version, `petra` has to be told about the meaning of the different methods of a class to be used inside a transaction.  
This decision was made as there are no strict conventions regarding method names in Ruby (e.g. `getX`/`setX` in Java).

`petra` knows about 5 different kinds of methods:

1. **Attribute Readers** which retrieve a current attribute value
2. **Attribute Writers** which set a new attribute value
3. **Dynamic Attribute Readers** which a composite methods like `name` (not an actual attribute, but use attributes interally)
4. **Persistence Methods** which save changes made to the object (think of `ActiveRecord::Base#save`)
5. **Destruction Methods** which remove the object


Let's create a configuration for `SimpleUser`:

```ruby
Petra.configure do
  configure_class SimpleUser do
    # Tell petra about our available attribute readers
    attribute_reader? do |method_name|
      %w[first_name last_name].include?(method_name.to_s)
    end
    
    # Do the same for attribute writers
    attribute_writer? do |method_name|
      %w[first_name= last_name=].include?(method_name.to_s)
      # also possible here: `method_name.last == '='`
    end    
    
    # Define which methods are used to persist instances of SimpleUser
    persistence_method? do |method_name|
      %w[first_name= last_name=].include?(method_name.to_s)
    end    

    # `name` uses attributes internally
    dynamic_attribute_reader? do |method_name|
      %[name].include?(method_name.to_s)
    end
  end
end
```

As you may have noticed, we used our `attribute_writer`s twice in this configuration: Once as actual attribute writers and once as persistence method. This was done to keep the example above as small as possible.

The same could have been achieved by setting up a no-op method and configuring it accordingly:

```ruby
# SimpleUser
def save; end

# Configuration
persistence_method { |method_name| %w[save].include?(method_name.to_s) } 

# Usage
Petra.transaction do
  user.first_name = 'Foo'
  user.save
end
```

In this case, not calling `save` inside the transaction would have lead to the loss of everything we did inside the transaction section.

### Commit / Rollback / Reset / Retry

#### Commit

Transactions can be committed by calling `Petra.commit!` inside a `Petra.transaction` block.  
It will leave the transaction block afterwards and not execute anything left in it:

```ruby
Petra.transaction do
  Petra.commit!
  puts 'I will never be shown!'
end
```

#### Rollback

A rollback can be triggered by either raising `Petra::Rollback` or simply any other uncaught `StandardError`. The difference is that `Petra::Rollback` will be swallowed by the transaction processing (like `ActiveRecord::Rollback` does), while any other error will be re-raised.

Triggering a rollback will undo all changes made **in the current section** of the transaction. All previous sections are not affected.

```ruby
Petra.transaction(identifier: 'tr1') do
  user.first_name = 'Foo'
end

Petra.transaction(identifier: 'tr1') do
  user.last_name = 'Bar'
  fail Petra::Rollback
end
```

In this example, only the change to `user#last_name` is lost.

#### Reset

A reset can be triggered by raising `Petra::Reset`. It works like a rollback, but will clear **the whole transaction**.

```ruby
Petra.transaction(identifier: 'tr1') do
  user.first_name = 'Foo'
end

Petra.transaction(identifier: 'tr1') do
  user.last_name = 'Bar'
  fail Petra::Reset
end
```

Here, all changes to `user` are lost.

#### Retry

A retry means that the current transaction block should be retried again after a rollback.  

```ruby
Petra.transaction(identifier: 'tr1') do
  user.last_name = 'Bar'
  fail Petra::Retry if some_condition
end
```

## Reacting to external changes

As the transaction is working in isolation on its own data set, it might happen that the original objects outside the transaction are changed in the meantime, e.g. by another transaction's commit:

```ruby
Petra.transaction(identifier: 'tr1') do
  user.first_name = 'Foo'
end

Petra.transaction(identifier: 'tr2') do
  user.first_name = 'Moo'
  Petra.commit!
end

Petra.transaction(identifier: 'tr1') do
  # we don't know about the external change here and would
  # possibly override it
end
```

`petra` reacts to these external changes and raises a corresponding exception. This exception allows the developer to solve the conflicts based on his current context.

The exception is thrown either when the attribute is used again or during the commit phase. Not handling any of these exception yourself will result in a transaction reset.

Each error described below shares a few common methods to control the further transaction flow:

```ruby
Petra.transaction(identifier: 'tr1') do
  begin
    ...
  rescue Petra::ValueComparisionError => e # Superclass of ReadIntegrityError and WriteClashError
    e.object          #=> the object which was changed externally
    e.attribute       #=> the name of the changed attribute
    e.external_value  #=> the new external value
  
    e.retry!    # Runs the current transaction block again
    e.rollback! # Dismisses all changes in the current section, continues after transaction block
    e.reset!    # Resets the whole transaction, continues after transaction block
    e.continue! # Continues with executing the current transaction block
  end
end
```

Please note that in most cases calling `rollback!`, `retry!` or `continue!` without any other exception specific method will result in the same error again the next time.

### An attribute we previously read was changed externally

A `ReadIntegrityError` is thrown if one transaction read an attribute value which is then changed externally:

```ruby
Petra.transaction(identifier: 'tr1') do
  user.last_name = 'the first' if user.first_name = 'Karl'
end

user.first_name = 'Olaf'

Petra.transaction(identifier: 'tr1') do
  user.first_name 
  #=> Petra::ReadIntegrityError: The attribute `first_name` has been changed externally.
end
```

When triggering a `ReadIntegrityError`, you can choose to acknowledge/ignore the external change. Doing so will suppress further errors as long as the external value does not change again.

```ruby
begin
...
rescue Petra::ReadIntegrityError => e
  e.last_read_value #=> the value we got when last reading the attribute

  e.ignore!(update_value: true)  # we acknowledge the external change and use the new value in our transaction from now on
  e.ignore!(update_value: false) # we keep our old value and simply ignore the external change.
  e.retry!
end
```

### An attribute we changed in our transaction was also changed externally

A `WriteClashError` is thrown whenever an attribute we changed inside one of our transaction sections was also changed externally:

```ruby
Petra.transaction(identifier: 'tr1') do
  user.first_name = 'Foo'
end

user.first_name = 'Moo'

Petra.transaction(identifier: 'tr1') do
  user.first_name
  #=> Petra:WriteClashError: The attribute `first_name` has been changed externally and in the transaction.
end
```

As both sides changed the attribute value, we have to decided which one to use further in most cases (or completely reset the transaction):

```ruby
begin
...
rescue Petra::WriteClashError => e
  e.our_value   #=> the value we set the attribute to
  e.their_value #=> the new external value

  e.use_theirs! # undo every change we made to the attribute in this transaction
  e.use_ours!   # Ignore the external change, use our value
  e.retry!
end
```

## Full Configuration Options

## Custom Proxy Classes

## How it works