require 'require_all'
require 'forwardable'

# Load all of petra's core files
require_all File.join(File.dirname(__FILE__), 'petra')

module Petra
  extend SingleForwardable

  def self.active_record?
    defined?(ActiveRecord::Base)
  end

  def self.rails?
    defined?(Rails)
  end

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
  # Attempts to commit the currently active transaction
  #
  def self.commit!
    transaction_manager.commit_transaction
  end

  #
  # @return [Petra::Components::TransactionManager, NilClass]
  #
  def self.transaction_manager
    Petra::Components::TransactionManager.instance
  end

  def_delegator :transaction_manager, :current_transaction

  #
  # Logs the given +message+
  #
  def self.logger
    Petra::Debug
  end
end

# Load the ActiveRecord models only if ActiveRecord itself is defined.
# TODO: Do not rely on Rails::Engine...
require_all Petra::Engine.root.join('app', 'models') if Petra.active_record?

# Extend the Object class to add the `petra` proxy generator
Object.class_eval do
  include Petra::CoreExt::Object
end

# Register Persistence Adapters
Petra::PersistenceAdapters::Adapter.register_adapter(:file, Petra::PersistenceAdapters::FileAdapter)
