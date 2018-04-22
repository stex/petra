[![Build Status](https://travis-ci.org/Stex/petra.svg?branch=master)](https://travis-ci.org/Stex/petra)

# petra
<img src="https://drive.google.com/uc?id=1BKauBWbE66keL1gBBDfgSaRE0lL5x586&export=download" width="200" align="right" />

Petra is a proof-of-concept for **pe**rsisted **tra**nsactions in Ruby.

Please note that this was created during my master's thesis in 2016 and hasn't been extended a lot since then except for a few coding style fixes. I would write a lot of stuff differently today, but the main concept is still interesting enough.

It allows starting a transaction without committing it and resuming it at a later time, even in another process - given the used objects provide identifiers other than `object_id`.

It should work with every Ruby object and can be extended to work with web frameworks like Ruby-on-Rails as well (a POC of RoR integration can be found at [stex/petra-rails](https://github.com/stex/petra-rails)). 

Let's take a look at how petra is used:

```ruby
class SimpleUser
  attr_accessor :first_name, :last_name
  
  def name
    "#{first_name} #{last_name}"
  end
  
  # We need at least a no-op for persistence, see below.
  def save
  end
  
  # ... configuration, see below
end

user = SimpleUser.petra.new
user.first_name, user.last_name = 'John', 'Doe'

# Start a new transaction and start changing attributes
Petra.transaction(identifier: 'tr1') do
  user.first_name = 'Foo'
  user.save
end

# No changes outside the transaction yet...
puts user.name #=> 'John Doe'

# Continue the same transaction
Petra.transaction(identifier: 'tr1') do
  puts user.name #=> 'Foo Doe'
  user.last_name = 'Bar'
  user.save
end

puts user.name #=> 'John Doe'

# Commit the transaction we built in the previous sections
Petra.transaction(identifier: 'tr1') do
  puts user.name #=> 'Foo Bar'
  Petra.commit!
end

# The actual object is finally updated
puts user.name #=> 'Foo Bar'
```

