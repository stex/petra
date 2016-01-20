module Petra
  module PersistenceAdapters

    #
    # This class acts as an interface and specifies the methods that
    # a transaction adapter has to implement.
    #
    class Adapter

      class << self
        def registered_adapters
          @adapters ||= {}
        end

        def registered_adapter(name)
          registered_adapters[name.to_s]
        end

        def register_adapter(name, klass)
          registered_adapters[name.to_s] = klass.to_s
        end

        def registered_adapter?(name)
          registered_adapters.has_key?(name.to_s)
        end

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

      protected

      #
      # @abstract
      #
      # Executes the given block after acquiring a global lock
      #
      def with_global_lock(&block)
        not_implemented
      end

      #
      # @abstract
      #
      # Executes the given block after acquiring a transaction based lock,
      # meaning that other processes which execute something in the same transaction's context
      # have to wait / abort
      #
      def with_transaction_lock(_identifier, &block)
        not_implemented
      end

      def queue
        @queue ||= []
      end

      def clear_queue!
        @queue = []
      end

    end
  end
end
