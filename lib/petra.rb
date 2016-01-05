require 'require_all'

# Load all of petra's core files
require_all File.join(File.dirname(__FILE__), 'petra')

# Load the ActiveRecord models only if ActiveRecord itself is defined.
require_all Petra::Engine.root.join('app', 'models') if defined?(ActiveRecord::Base)

module Petra

  #
  # @return [Petra::Configuration::Base] petra's configuration instance
  #
  def self.configuration
    @configuration ||= Petra::Configuration::Base.new
  end

  #
  # Executes the given block in the context of petra's configuration instance
  #
  def self.configure(&proc)
    configuration.instance_eval(&proc) if block_given?
  end

  #
  # Forward transaction handling to the TransactionManager class
  #
  # @see Petra::Components::TransactionManager#with_transaction
  #
  def self.transaction(identifier: SecureRandom.uuid, &block)
    Petra::Components::TransactionManager.with_transaction(identifier: identifier, &block)
  end

  #
  # @return [Petra::Components::TransactionManager, NilClass]
  #
  def self.transaction_manager
    Petra::Components::TransactionManager.instance
  end

  #
  # Logs the given +message+ if petra is configured to be verbose
  #
  def self.log(*args)
    return unless configuration.verbose
    Petra::Debug.log(*args)
  end

end

# Extend the Object class to add the `petra` proxy generator
Object.class_eval do
  include Petra::CoreExt::Object
end