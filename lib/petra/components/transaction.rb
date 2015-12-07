module Petra
  module Components
    class Transaction

      def initialize(identifier:)
        @identifier = identifier
      end

      #
      # Tries to commit the current transaction
      #
      def commit

      end

      #
      # Performs a rollback on this transaction, meaning that it will be set
      # to the state of the latest savepoint
      #
      def rollback

      end

      #
      # Persists the current transaction section using the configured persistence adapter
      #
      def persist

      end

      #
      # Completely dismisses the current transaction and removes it from the persistence storage
      #
      def reset

      end

      private

      def persistence_adapter

      end

    end
  end
end
