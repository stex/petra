# frozen_string_literal: true
require 'petra/util/registrable'

module Petra
  module PersistenceAdapters

    #
    # This class acts as an interface and specifies the methods that
    # a transaction adapter has to implement.
    #
    class Adapter
      include Petra::Util::Registrable
      acts_as_register :adapter

      class << self
        alias_method :[], :registered_adapter
      end

      #
      # @abstract
      #
      # Persists the transaction steps which happened after
      # the last changes were persisted.
      #
      def persist!
        not_implemented
      end

      #
      # Adds the given log entry to the queue to be persisted next.
      # Fails if the queue already contains the log entry.
      #
      # @param [Petra::Components::LogEntry] log_entry
      #
      def enqueue(log_entry)
        if queue.include?(log_entry)
          fail Petra::PersistenceError, 'A log entry can only be added to a persistence queue once'
        end
        queue << log_entry
      end

      #
      # @abstract
      #
      # @return [Array<String>] the identifiers of all transactions which are
      #   currently persisted (>= one section finished, but not committed)
      #
      def transaction_identifiers
        not_implemented
      end

      #
      # @abstract
      #
      # @param [Petra::Components::Transaction] transaction
      #
      # @return [Array<String>] the names of all savepoints which were previously persisted
      #   for the given transaction
      #
      def savepoints(transaction)
        not_implemented
      end

      #
      # @abstract
      #
      # @param [Petra::Components::Section] section
      #
      # @return [Array<Petra::Components::LogEntry>] All log entries which were previously
      #   persisted for the given section
      #
      def log_entries(section)
        not_implemented
      end

      #
      # Resets the given transaction, meaning that all persisted information is removed
      #
      def reset_transaction(_transaction)
        not_implemented
      end

      #
      # @abstract
      #
      # Executes the given block after acquiring a global lock
      #
      # The actual implementation must ensure that an acquired lock is released in case of
      # an exception!
      #
      # @param [Boolean] suspend
      #   If set to +false+, the method will not suspend if the global lock could not be
      #   acquired. Instead, a Petra::LockError is thrown
      #
      # @raise [Petra::LockError] see +suspend+
      #
      def with_global_lock(suspend: true, &block)
        not_implemented
      end

      #
      # @abstract
      #
      # Executes the given block after acquiring a transaction based lock,
      # meaning that other processes which execute something in the same transaction's context
      # have to wait / abort
      #
      # The actual implementation must ensure that an acquired lock is released in case of
      # an exception!
      #
      # @param [Boolean] suspend
      #   If set to +false+, the method will not suspend if the transaction lock could not be
      #   acquired. Instead, a Petra::LockError is thrown
      #
      # @raise [Petra::LockError] see +suspend+
      #
      def with_transaction_lock(_identifier, suspend: true, &block)
        not_implemented
      end

      #
      # @abstract
      #
      # Executes the given block after acquiring the lock for the given proxy (object)
      #
      # The actual implementation must ensure that an acquired lock is released in case of
      # an exception!
      #
      # @param [Petra::Proxies::ObjectProxy] _proxy
      #
      # @param [Boolean] suspend
      #   See #with_global_lock
      #
      # @raise [Petra::LockError]
      #
      def with_object_lock(_proxy, suspend: true, &block)
        not_implemented
      end

      protected

      def queue
        @queue ||= []
      end

      def clear_queue!
        @queue = []
      end
    end
  end
end
