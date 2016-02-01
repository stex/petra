require 'active_support/all'
require 'pathname'

require 'petra/core_ext'
require 'petra/exceptions'
require 'petra/configuration/base'
require 'petra/configuration/class_configurator'
require 'petra/util/debug'
require 'petra/persistence_adapters/file_adapter'

require 'petra/proxies/enumerable_proxy'
require 'petra/proxies/object_proxy'

require 'petra/components/transaction_manager'

require 'petra/components/entries/attribute_change'
require 'petra/components/entries/attribute_change_veto'
require 'petra/components/entries/attribute_read'
require 'petra/components/entries/object_destruction'
require 'petra/components/entries/object_initialization'
require 'petra/components/entries/object_persistence'
require 'petra/components/entries/read_integrity_override'

require 'forwardable'

module Petra
  extend SingleForwardable

  def self.root
    Pathname.new(File.dirname(__FILE__))
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
  def self.transaction(identifier: nil, &block)
    Petra::Components::TransactionManager.with_transaction(identifier: identifier || SecureRandom.uuid, &block)
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
    Petra::Util::Debug
  end

  def self.rails?
    defined?(Rails)
  end
end

# Extend the Object class to add the `petra` proxy generator
Object.class_eval do
  include Petra::CoreExt::Object
end

# Register Persistence Adapters
Petra::PersistenceAdapters::Adapter.register_adapter(:file, Petra::PersistenceAdapters::FileAdapter)
