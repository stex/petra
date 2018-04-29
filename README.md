[![Build Status](https://travis-ci.org/Stex/petra.svg?branch=master)](https://travis-ci.org/Stex/petra)

# petra
<img src="https://drive.google.com/uc?id=1BKauBWbE66keL1gBBDfgSaRE0lL5x586&export=download" width="200" align="right" />

Petra is a proof-of-concept for **pe**rsisted **tra**nsactions in Ruby with (hopefully) full ACI(D) properties.

Please note that this was created during my master's thesis in 2016 and hasn't been extended a lot since then except for a few coding style fixes. I would write a lot of stuff differently today, but the main concept is still interesting enough.

It allows starting a transaction without committing it and resuming it at a later time, even in another process - given the used objects provide identifiers other than `object_id`.

It should work with every Ruby object and can be extended to work with web frameworks like Ruby-on-Rails as well (a POC of RoR integration can be found at [stex/petra-rails](https://github.com/stex/petra-rails)). 

This README only covers parts of what `petra` has to offer. Feel free to dive into the code, everything should be commented accordingly.

Let's take a look at how `petra` is used:

```ruby
class SimpleUser
  attr_accessor :first_name, :last_name
  
  def name
    "#{first_name} #{last_name}"
  end
  
  # ... configuration, see below
end

user = SimpleUser.petra.new('John', 'Doe')

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

# Another transaction changes a value already changed in 'tr1'
Petra.transaction do
  user.first_name = 'Moo'
  Petra.commit!
end

puts user.name #=> 'Moo Doe'

# Try to commit our first transaction
Petra.transaction(identifier: 'tr1') do
  puts user.name
  Petra.commit!
rescue Petra::WriteClashError => e
  # => "The attribute `first_name` has been changed externally and in the transaction. (Petra::WriteClashError)"
  # Let's use our value and go on with committing the transaction
  e.use_ours!
  e.continue!
end

# The actual object is updated with the values from tr1
puts user.name #=> 'Foo Bar'
```

We just used a simple Ruby object inside a transaction which was even split into multiple sections! 

(The full example can be found at [`examples/showcase.rb`](https://github.com/Stex/petra/blob/master/examples/showcase.rb))

<!-- START doctoc generated TOC please keep comment here to allow auto update -->
<!-- DON'T EDIT THIS SECTION, INSTEAD RE-RUN doctoc TO UPDATE -->
## TOC

- [Installation](#installation)
- [Basic Usage](#basic-usage)
  - [Starting/Resuming a transaction](#startingresuming-a-transaction)
  - [Transactional Objects and their Configuration](#transactional-objects-and-their-configuration)
  - [Commit / Rollback / Reset / Retry](#commit--rollback--reset--retry)
- [Reacting to external changes](#reacting-to-external-changes)
  - [An attribute we previously read was changed externally](#an-attribute-we-previously-read-was-changed-externally)
  - [An attribute we changed in our transaction was also changed externally](#an-attribute-we-changed-in-our-transaction-was-also-changed-externally)
  - [`continue!`?](#continue)
- [Full Configuration Options](#full-configuration-options)
  - [Global Options](#global-options)
  - [Class Specific Options](#class-specific-options)
- [Extending `petra`](#extending-petra)
  - [Class Proxies](#class-proxies)
  - [Module Proxies](#module-proxies)
  - [Persistence Adapters](#persistence-adapters)

<!-- END doctoc generated TOC please keep comment here to allow auto update -->

## Installation

Simply add the following line to your gemfile:

```ruby
gem 'petra_core', require: 'petra'
```
    
Unfortunately, the gem name `petra` is already taken and `petra-core` would express that this gem is extending it, so 
I went for an underscore for now. It's hard finding nice-sounding gem names which are not yet taken nowadays :/

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

A `ReadIntegrityError` is thrown if one transaction reads an attribute value which is then changed externally:

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

### `continue!`?

As mentioned above, `petra` allows the developer to jump back into the transaction after an error was resolved.  
This is done by using Ruby's [Continuation](https://ruby-doc.org/core-2.5.0/Continuation.html) which basically saves a copy of the stack at the time the exception happened. This copy can then be restored if the developer decides to continue the execution.

I'd personally keep everything regarding continuations far away from production code, but they are a very interesting concept (which will most likely be removed with Ruby 3.0 :/ ). `examples/continuation_error.rb` shows one of the drawbacks which could lead to a long time of debugging.

```ruby
begin
  simple_user.first_name = 'Foo'
  simple_user.save
rescue Petra::WriteClashError => e
  e.use_ours!
  # Jumps back to `simple_user.save` without a retry
  e.continue!
end
```

## Full Configuration Options

### Global Options

#### `persistence_adapter`

```ruby
Petra.configure do
  persistence_adapter :file
  persistence_adapter.storage_directory = '/tmp/petra'
end
```

Specifies the persistence adapter and its possible options.  
Petra only includes a file system based adapter by default.

#### `instantly_fail_on_read_integrity_errors`

```ruby
Petra.configure do
  instantly_fail_on_read_integrity_errors false
end	
```

`petra` can be set to optimistic transaction handling. This means, that a transaction is only checked
for possible external changes during the commit phase.

By default, a corresponding error is thrown directly when the attribute is accessed again within the transaction.

#### `log_level`

```ruby
Petra.configure do
  log_level :debug | :info | :warn | :error
end
```

Specifies the log level `petry` should use. 

* `:debug`
	* Information about all methods called on an object proxy and their results
	* Attribute reads and changes
	* Acquired and released locks
	* The creation of transaction log entries
* `:info`
	* Starting and persisting a transaction
	* Committing a transaction
	* Triggering a rollback on a transaction
* `:warn`
	* Forced transaction resets

### Class Specific Options

Apart from the already mentioned ones, the following class specific options are available:

#### `proxy_instances`

Determines whether `petra` should automatically create proxies for instances of the configured class when they are accessed from within an existing object proxy.

```ruby
Petra.configure do
  configure_class SimpleUser do
    proxy_instances true
  end
  
  # Do not create a proxy for strings. Otherwise, calling `SimpleUser#first_name` would result in a string object proxy
  configure_class String do
    proxy_instances false
  end
end
```

#### `use_specialized_proxy`

`petra` contains a very basic `ObjectProxy` implementation which works fine with most ruby objects, but has to be configured.  
For more advanced classes, it is advised to create a specialized proxy (see `petra-rails`).

By default, `petra` will use the specialized version if available, but can be forced to use the basic object proxy instead:

```ruby
Petra.configure do
  configure_class ActiveRecord::Base do
    use_specialized_proxy false
  end
end
```

#### `mixin_module_proxies`

`petra` does not only support proxies for certain classes, but also for mixins. This allows a developer to define a proxy which is automatically used for every class which contains a certain module.

By default, `petra` contains an `Enumerable` proxy which automatically wraps its entries in object proxies.

The automatic inclusion of these module proxies can be disabled:

```ruby
Petra.configure do
  configure_class Array do
    mixin_module_proxies false
  end
end
```

#### `id_method`

Specifies the method to retrieve an identifier for instances of the configured class.

By default, `object_id` is used, which of course is very limited. 

```ruby
Petra.configure do
  configure_class ActiveRecord::Base do
    id_method :id
    # or
    id_method do |obj|
      obj.id
    end
  end
end
```

#### `lookup_method`

Basically the counterpart of `id_method`. Specifies the class method which can be used to retrieve an instance of the configured class when providing the corresponding identifier.

It defaults to `ObjectSpace._id2ref` which returns an object by its `object_id`.

```ruby
Petra.configure do
  configure_class ActiveRecord::Base do
    lookup_method :find
  end
end
```

#### `init_method`

Specifies the method to initialize a new instance of the configured class (or one of its descendants).  
It is used to automatically re-initialize objects used (and persisted) in a previous section and works the same way as lookup_method.

```ruby
Petra.configure do
  configure_class Array do
    init_method :new
  end
end
```

## Extending `petra`

`petra` can be easily extended to a certain extent as seen in [stex/petra-rails](https://github.com/stex/petra-rails).

### Class Proxies

As mentioned above, some classes are too complicated to be configured using the basic `ObjectProxy`.

Let's define a basic example for such a class:

```ruby
class SimpleRecord
  def self.create(attributes = {})
    new(attributes).save
  end
  
  def save
    # some persistence logic
  end
end
```

In this example, `#create` is a method we cannot configure easily as it doesn't match any of the available method types in `ObjectProxy`. Instead. it is a combination of attribute writers and persistence methods.

To be taken into account as a custom object proxy, a class has to comply to the following rules:

1. It has to be defined inside `Petra::Proxies`
2. It has to inherit from `Petra::Proxies::ObjectProxy`
3. It has to define the class names it may be applied to in a constant named `CLASS_NAMES`

Let's define the corresponding proxy for `SimpleRecord`:

```ruby
module Petra
  module Proxies
    class SimpleRecordProxy < ObjectProxy
      CLASS_NAMES = %w[SimpleRecord].freeze

      def create(attributes = {})
        # This method may only be called on class, not on instance level
        class_method!

        # Use ObjectProxy's basic `new` method without any arguments
        new.tap do |obj|
          # Tell our transaction that we initialized a new object.
          # This wasn't done in the previous examples as we were working on the
          # `ObjectSpace` with objects defined outside the transaction.
          transaction.log_object_initialization(o, method: 'new')

          # Apply the attribute writes inside the transaction
          attributes.each do |k, v|
            __set_attribute(k, v)
          end

          # #create automatically persists a record, we therefore have to
          # tell our transaction to log this action.
          transaction.log_object_persistence(o, method: 'save')
        end
      end

      def save
        transaction.log_object_persistence(self, method: 'save')
      end
    end
  end
end
```

See [petra-rails's ActiveRecordProxy](https://github.com/Stex/petra-rails/blob/master/lib/petra/proxies/active_record_proxy.rb) for a full example.

### Module Proxies

As mentioned above, module proxies can be used to define proxy functionality for all classes which include a certain module.  
Internally, these modules are included into the singleton class of our object proxies, meaning that one instance of a proxy could include a certain module, the other doesn't.

A module proxy has to comply to the following rules:

1. It has to be defined in `Petra::Proxies`
2. It has to include `Petra::Proxies::ModuleProxy`
3. It has to define a constant named `MODULE_NAMES` which contains the modules it is applicable for.

Let's take a look at `petra`'s `EnumerableProxy`:

```ruby
module Petra
  module Proxies
    module EnumerableProxy
      include ModuleProxy
      MODULE_NAMES = %w[Enumerable].freeze

      # Specifying an `INCLUDES` constant leads to instances of the resulting proxy
      # automatically including the given modules - in this case, every proxy which handles
      # an Enumerable will automatically be an Enumerable as well
      INCLUDES = [Enumerable].freeze

      # ModuleProxies may specify an `InstanceMethods` and a `ClassMethods` sub-module.
      # Their methods will be included/extended accordingly.
      module InstanceMethods
        #
        # We have to define our own #each method for the singleton class' Enumerable
        # It basically just wraps the original enum's entries in proxies and executes
        # the "normal" #each
        #
        def each(&block)
          Petra::Proxies::EnumerableProxy.proxy_entries(proxied_object).each(&block)
        end
      end

      #
      # Ensures the the objects yielded to blocks are actually petra proxies.
      # This is necessary as the internal call to +each+ would be forwarded to the
      # actual Enumerable object and result in unproxied objects.
      #
      # This method will only proxy objects which allow this through the class config
      # as the enum's entries are seen as inherited objects.
      # `[]` is used as method causing the proxy creation as it's closest to what's actually happening.
      #
      # @return [Array<Petra::Proxies::ObjectProxy>]
      #
      def self.proxy_entries(enum, surrogate_method: '[]')
        enum.entries.map { |o| o.petra(inherited: true, configuration_args: [surrogate_method]) }
      end
    end
  end
end
```

Please take a look at [`lib/petra/proxies/abstract_proxy.rb`](https://github.com/Stex/petra/blob/master/lib/petra/proxies/abstract_proxy.rb) for more information regarding how proxies are chosen and built.

### Persistence Adapters

For its transaction handling, `petra` needs access to a storage with atomic write operations to store its transaction logs as well as being able to lock certain resources (during commit phase, no other transaction may have access to certain resources).

[`Petra::PersistenceAdapters::Adapter`](https://github.com/Stex/petra/blob/master/lib/petra/persistence_adapters/adapter.rb) provides an interface for classes which provide this functionality. [`FileAdapter`](https://github.com/Stex/petra/blob/master/lib/petra/persistence_adapters/file_adapter.rb) is the reference implementation which uses the file system and UNIX file locks.

#### Required Methods

**`persist!`**

Saves all available transaction log entries to the storage.
Log entries are added using `#enqueue(entry)` and available as `queue` inside your adapter instance.

* A transaction lock has to be applied
* Entries have to be marked as persisted afterwards using `entry.mark_as_persisted!`


**`transaction_identifiers`**

Should return the identifiers of all transactions which were started, but not yet committed.

**`savepoints(transaction)`**

Should return all savepoints (section identifiers) for the given transaction,

**`log_entries(section)`**

Should return all log entries which were persisted for the given section in the past.

**`reset_transaction(transaction)`**

Removes all information currently stored regarding the given transaction

**`with_global_lock(suspend:, &block)`**

Acquires a global lock (only one thread may hold it at the same time), runs the given block and releases the global lock again.

If `suspend` is set to `true`, the execution will wait for the lock to be available, otherwise, a `Petra::LockError` is thrown if the lock is not available.

You have to make sure that the lock is freed again if an error occurs within the given block or your own implementation.

**`with_transaction_lock(transaction, suspend:)`**

Acquires a lock on the given transaction.

**`with_object_lock(object, suspend:)`**

Acquires a lock on the given Object (Proxy). 

Make sure that your implementation allows one thread locking the resource multiple times without stalling.

```ruby
with_object_lock(obj1) do
  with_object_lock(obj1) do # Should work as we already hold the lock
   ...
  end
end 
```


#### Registering a new adapter

Similar to Rails' mailer adapters, new adapter can be registered under a given name and be used in `petra`'s configuration afterwards:

```ruby
Petra::PersistenceAdapters::Adapter.register_adapter(:redis, RedisAdapter)

Petra.configure do
  persistence_adapter :redis
end
```
