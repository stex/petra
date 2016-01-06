module Petra
  module Components
    class Transaction

      attr_reader :identifier
      attr_reader :persisted
      attr_reader :committed

      alias_method :persisted?, :persisted
      alias_method :committed?, :committed

      delegate :log_attribute_change, :log_object_persistence, :to => :current_section

      def initialize(identifier:)
        @identifier = identifier
        @persisted  = false
        @committed  = false
      end

      #----------------------------------------------------------------
      #                          Log Entries
      #----------------------------------------------------------------

      #
      # Returns the latest value which was set for a certain object attribute.
      # This means that all previous sections' write sets are inspected from new to old.
      #
      # @see Petra::Components::Section#value_for for more information
      #
      def attribute_value(proxy, attribute:)
        sections.reverse.find { |s| s.value_for?(proxy, attribute: attribute) }.value_for(proxy, attribute: attribute)
      end

      #
      # @return [Boolean] +true+ if one of the previous write sets contains a value for
      #   the given attribute
      #
      def attribute_value?(proxy, attribute:)
        sections.reverse.any? { |s| s.value_for?(proxy, attribute: attribute) }
      end

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
        current_section.enqueue_for_persisting!
        persistence_adapter.persist!

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
