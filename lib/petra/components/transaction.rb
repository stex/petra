module Petra
  module Components
    class Transaction

      attr_reader :persisted
      attr_reader :committed

      alias_method :persisted?, :persisted
      alias_method :committed?, :committed

      def initialize(identifier:)
        @identifier = identifier
        @persisted  = false
        @committed  = false
      end

      #
      # Tries to commit the current transaction
      #
      def commit
        @committed = true
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
        Petra.log "Persisted transaction #{@identifier} ... I guess", :green

        @persisted = true
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
