# frozen_string_literal: true

$LOAD_PATH << File.join(File.dirname(__FILE__), '..', 'lib')
$LOAD_PATH << File.join(File.dirname(__FILE__), '..', 'spec', 'support', 'classes')
require 'petra'
require 'simple_user'
require 'simple_user_with_auto_save'

Petra.configure do
  log_level :warn
end

def log(message, identifier = 'External')
  puts [identifier, message].join(': ')
end

user = Classes::SimpleUserWithAutoSave.petra.new('John', 'Doe')

# Start a new transaction and start changing attributes
Petra.transaction(identifier: 'tr1') do
  user.first_name = 'Foo'
end

# No changes outside the transaction yet...
log user.name #=> 'John Doe'

# Continue the same transaction
Petra.transaction(identifier: 'tr1') do
  log(user.name, 'tr1') #=> 'Foo Doe'
  user.last_name = 'Bar'
end

# Another transaction changes a value already changed in 'tr1'
Petra.transaction(identifier: 'tr2') do
  log(user.name, 'tr2') #=> John Doe
  user.first_name = 'Moo'
  Petra.commit!
end

log user.name #=> 'Moo Doe'

# Try to commit our first transaction
Petra.transaction(identifier: 'tr1') do
  log(user.name, 'tr1')
  Petra.commit!
rescue Petra::WriteClashError => e
  # => "The attribute `first_name` has been changed externally and in the transaction. (Petra::WriteClashError)"
  # Let's use our value and go on with committing the transaction
  e.use_ours!
  e.continue!
end

# The actual object is updated with the values from tr1
log user.name #=> 'Foo Bar'
