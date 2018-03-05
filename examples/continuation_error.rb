# frozen_string_literal: true

$: << File.join(File.dirname(__FILE__), '..', 'lib')
$: << File.join(File.dirname(__FILE__), '..', 'spec', 'support')
require 'petra'
require 'faker'

#
# This example shows why continuations and production code / code
# that uses external libraries are not a good combination.
#

#----------------------------------------------------------------
#                    Sample Class Definitions
#----------------------------------------------------------------

class SimpleUser
  attr_accessor :first_name
  attr_accessor :last_name

  def initialize
    @first_name, @last_name = Faker::Name.name.split(' ')
  end

  def save
    # Do nothing, we just want an explicit save method.
    # We could also set every attribute write to also be a persistence method
  end
end

Petra.configure do
  configure_class 'SimpleUser' do
    proxy_instances true

    attribute_reader? do |method_name|
      %w[first_name last_name].include?(method_name.to_s)
    end

    attribute_writer? do |method_name|
      %w[first_name= last_name=].include?(method_name.to_s)
    end

    persistence_method? do |method_name|
      %w[save].include?(method_name.to_s)
    end
  end
end

class ConfidentialData < String
  def read?
    !!@read
  end

  def read!
    @read = true
  end
end

class SimpleHandler
  def with_confidential_data(string)
    @confidential_data = ConfidentialData.new(string)
    yield
  rescue Exception
    # The data might have been compromised! Delete it!
    @confidential_data = nil
    raise
  end

  def do_confidential_stuff(user)
    puts "User #{user.first_name} #{user.last_name} is very confidential."
    user.last_name = user.last_name + ' ' + ('I' * @confidential_data.length) + '.'
  ensure
    @confidential_data.read!
  end
end

#----------------------------------------------------------------
#                        Helper Methods
#----------------------------------------------------------------

# rubocop:disable Security/Eval
def transaction(id_no)
  Petra.transaction(identifier: eval("$t_id_#{id_no}", __FILE__, __LINE__)) do
    begin
      yield
    rescue Petra::ValueComparisonError => e
      e.ignore!
      e.continue!
    end
  end
end
# rubocop:enable Security/Eval

#----------------------------------------------------------------
#                        Actual Example
#----------------------------------------------------------------

# Create 2 transaction identifiers
$t_id_1 = Petra.transaction {}
$t_id_2 = Petra.transaction {}

# Instantiate a handler and a SimpleUser object proxy
handler = SimpleHandler.new
user    = SimpleUser.petra.new

transaction(1) do
  user.first_name
  user.last_name = Faker::Name.last_name
  user.save
end

transaction(2) do
  user.first_name, user.last_name = Faker::Name.name.split(' ')
  user.save
  Petra.commit!
end

transaction(1) do
  handler.with_confidential_data('Ulf.') do
    handler.do_confidential_stuff(user) #=> Undefined method #read! for nil:NilClass...
  end
end
