module Petra
  module Components
    #
    # A transaction manager handles the transactions in a single petra section,
    # when speaking in terms of Rails, a new transaction manager is built every request.
    #
    # Each TransactionManager has a stack of transactions which are currently active and
    # is currently stored within the current thread space. Once all active transactions
    # are either persisted or otherwise finished, it is removed again to (more or less)
    # ensure thread safety.
    #
    module TransactionManager

      #
      # Performs the given block on the current instance of TransactionManager.
      # For nested transactions, the outer transaction manager is re-used,
      # for outer transactions, a new manager is created.
      #
      def self.within_instance(&block)
        instance = Thread.current[:__petra_transaction_manager] ||= TransactionManager.new
        begin
          instance.instance_eval(&block)
        ensure
          if instance && instance.transaction_count.zero?
            Thread.current[:__petra_transaction_manager] = nil
          end
        end
      end

      def initialize
        @stack = []
      end

      #
      # Resets the currently innermost transaction.
      # This means that everything this transaction has done so far will be
      # discarded and the identifier freed again.
      # TODO: Nested transactions again, what would happen?
      #
      def reset_transaction
        @stack.pop.reset
      end

      #
      # Performs a rollback on the currently innermost transaction.
      # This means that everything up until the transaction's latest
      # savepoint will be discarded.
      # TODO: Can we jump to a custom savepoint? What would happen if we were using the outer transaction's data?
      #
      def rollback_transaction
        @stack.pop.rollback
      end

      #
      # Commits the currently innermost transaction
      #
      def commit_transaction
        @stack.pop.commit
      end

      #
      # Persists the currently innermost transaction, meaning that its actions will be
      # written to storage using the chosen persistence adapter.
      # This usually happens when a #with_transaction block ends and no commit flag
      # was set using the corresponding exception class
      #
      def persist_transaction
        @stack.pop.persist
      end

      #
      # Wraps the given block in a petra transaction (section)
      #
      # @param [String] identifier
      #   The transaction's identifier. For continued transaction it has to be
      #   the same in each request, otherwise, a new transaction is started instead.
      #
      # @return [String] the transaction's identifier
      #
      def self.with_transaction(identifier: SecureRandom.uuid)
        within_instance do
          begin
            transaction = begin_transaction(identifier)
            yield
          rescue Petra::Rollback => error
            rollback_transaction
          rescue Petra::Commit => error
            commit_transaction
          rescue Petra::Reset => error
            reset_transaction
          rescue Exception => error
            # If another exception happened, we perform a rollback on the current
            # transaction section and raise the exception again so a possible
            # outer transaction may handle it as well.
            rollback_transaction
            raise
          ensure
            # If we made it through the transaction section without raising
            # any exception, we simply want to persist the performed transaction steps.
            # If an exception happens during this persistence,
            # a simple rollback is triggered as long as the transaction wasn't already persisted.
            # TODO: See if this behaviour could cause trouble
            unless error
              begin
                persist_transaction
              rescue Exception
                transaction.rollback unless transaction.persisted?
                raise
              end
            end
          end
        end

        identifier
      end

      def persistence
        @persistence_adapter ||= Petra.configuration.persistence_adapter.new
      end

      #
      # @return [Fixnum] the number of currently active transactions
      #
      def transaction_count
        @stack.size
      end

      def current_transaction
        @stack.last
      end

      private

      #
      # Starts a new transaction and pushes it to the transaction stack.
      # If one or more transactions are already running, a sub-transaction with a section
      # savepoint name is started which can be rolled back individually
      #
      def begin_transaction(identifier)
        Transaction.new(identifier: identifier).tap do |t|
          @stack.push(t)
        end
      end
    end
  end
end
