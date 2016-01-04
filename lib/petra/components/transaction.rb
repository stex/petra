module Petra
  module Components
    class Transaction

      attr_reader :identifier
      attr_reader :persisted
      attr_reader :committed

      alias_method :persisted?, :persisted
      alias_method :committed?, :committed

      delegate :log_attribute_change, :to => :current_section

      def initialize(identifier:)
        @identifier = identifier
        @persisted  = false
        @committed  = false
      end

      #----------------------------------------------------------------
      #                          Log Entries
      #----------------------------------------------------------------



      #----------------------------------------------------------------
      #                           Sections
      #----------------------------------------------------------------

      def current_section
        @section ||= Petra::Components::Section.new(self).tap do |s|
          @sections << s
        end
      end

      def sections
        @sections ||= []
      end

      #----------------------------------------------------------------
      #                        Transaction Handling
      #----------------------------------------------------------------

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
        Petra.transaction_manager.persistence_adapter
      end

    end
  end
end
