module Petra
  module Components
    class Transaction

      attr_reader :identifier
      attr_reader :persisted
      attr_reader :committed
      attr_reader :reset

      alias_method :persisted?, :persisted
      alias_method :committed?, :committed
      alias_method :reset?, :reset

      delegate :log_attribute_change,
               :log_object_persistence,
               :log_attribute_read,
               :log_object_initialization,
               :log_object_destruction, :to => :current_section

      def initialize(identifier:)
        @identifier = identifier
        @persisted  = false
        @committed  = false
        @reset      = false

        # Initialize the current section
        current_section
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

      #
      # @return [Boolean] +true+ if the given attribute was read in one of the previous (or the current) sections
      #
      def read_attribute_value?(proxy, attribute:)
        sections.reverse.any? { |s| s.read_value_for?(proxy, attribute: attribute) }
      end

      #
      # @return [Object] the last read value for the given attribute
      #
      def read_attribute_value(proxy, attribute:)
        sections.reverse.find { |s| s.read_value_for?(proxy, attribute: attribute) }
            .read_value_for(proxy, attribute: attribute)
      end

      #----------------------------------------------------------------
      #                        Attribute Helpers
      #----------------------------------------------------------------

      #
      # Checks whether the given attribute has been changed since we last read it.
      # Raises an exception if the attribute was changed externally
      #
      # We cannot check here whether the attribute had several different values before
      # going back to the original one, so we only compare the current and the last read value.
      #
      def verify_attribute_integrity!(proxy, attribute:)
        # If we didn't read the attribute before, we can't search for changes
        return unless read_attribute_value?(proxy, attribute: attribute)

        # New objects won't be changed externally...
        return if proxy.__new?

        # Check whether the actual attribute value still equals the one we last read
        if proxy.unproxied.send(attribute) != read_attribute_value(proxy, attribute: attribute)
          fail Petra::ReadIntegrityError, "The attribute `#{attribute}` has been changed externally."
        end
      end

      #----------------------------------------------------------------
      #                         Object Helpers
      #----------------------------------------------------------------

      def objects
        @objects ||= TransactionalObjects.new(self)
      end

      #----------------------------------------------------------------
      #                           Sections
      #----------------------------------------------------------------

      def current_section
        @section ||= Petra::Components::Section.new(self).tap do |s|
          sections << s
        end
      end

      def sections
        @sections ||= persistence_adapter.savepoints(self).map do |savepoint|
          Petra::Components::Section.new(self, savepoint: savepoint)
        end.sort_by(&:savepoint_version)
      end

      #----------------------------------------------------------------
      #                        Transaction Handling
      #----------------------------------------------------------------

      #
      # Tries to commit the current transaction
      #
      def commit!
        sections.each do |section|

        end

        @committed = true
        Petra.logger.info "Committed transaction #{@identifier}", :green
      end

      #
      # Performs a rollback on this transaction, meaning that it will be set
      # to the state of the latest savepoint.
      # The current section will be reset, but keep the same savepoint name.
      #
      def rollback!
        current_section.reset!
        Petra.logger.warn "Rolled back transaction #{@identifier}", :green
      end

      #
      # Persists the current transaction section using the configured persistence adapter
      #
      def persist!
        current_section.enqueue_for_persisting!
        persistence_adapter.persist!
        Petra.logger.debug "Persisted transaction #{@identifier}", :green
        @persisted = true
      end

      #
      # Completely dismisses the current transaction and removes it from the persistence storage
      #
      def reset!
        persistence_adapter.reset_transaction(self)
        @sections = []
        Petra.logger.warn "Reset transaction #{@identifier}", :red
      end

      private

      #
      # @return [Petra::PersistenceAdapters::Adapter] the current persistence adapter
      #
      def persistence_adapter
        Petra.transaction_manager.persistence_adapter
      end

    end
  end
end
