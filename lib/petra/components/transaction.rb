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
      # @param [Boolean] force
      #   If set to +true+, the check is performed even if it was disabled in the
      #   base configuration.
      #
      # @raise [Petra::ReadIntegrityError] Raised if the attribute value changed since
      #   we last read it.
      #
      def verify_attribute_integrity!(proxy, attribute:, force: false)
        # If we didn't read the attribute before, we can't search for changes
        return unless read_attribute_value?(proxy, attribute: attribute)

        # Don't perform the check if the force flag is not set and
        # petra is configured to not fail on read integrity errors at all.
        return if !force && !Petra.configuration.instant_read_integrity_fail

        # New objects won't be changed externally...
        return if proxy.__new?

        # Check whether the actual attribute value still equals the one we last read
        if proxy.unproxied.send(attribute) != read_attribute_value(proxy, attribute: attribute)
          exception = Petra::ReadIntegrityError.new(attribute: attribute, object: proxy)
          fail exception, "The attribute `#{attribute}` has been changed externally."
        end
      end

      #----------------------------------------------------------------
      #                         Object Helpers
      #----------------------------------------------------------------

      def objects
        @objects ||= ProxyCache.new(self)
      end

      #
      # Undo all the changes made to this proxy within the current section
      # TODO: Think about if that's something you'd really want to do... other changes might
      #   rely on this object...
      # TODO: Reset the object in the whole transaction?
      #
      def reset_object!(proxy)
        current_section.reset_object!(proxy)
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
        # TODO: Acquire the transaction lock once here, otherwise, every section will do it.
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
        # Step 1: Lock this transaction so no other thread may alter it any more
        persistence_adapter.with_transaction_lock(identifier) do
          begin
            # Step 2: Try to get the locks for all objects which took part in this transaction
            #   Acquire the locks on a sorted collection to avoid Deadlocks with other transactions
            # We do not have to lock objects which were created within the transaction
            #   as the cannot be altered outside of it and the transaction itself is locked.
            with_locked_objects(objects.fateful.sort.reject(&:__new?), suspend: false) do
              # Step 3: Now that we got locks on all objects used during this transaction,
              #   we can check whether all read attributes still have the same value.
              #   If that's not the case, we may not proceed.
              objects.verify_read_attributes!(force: true)

              # Step 4: Now that we know that all read values are still valid,
              #   we may actually apply all the changes we previously logged.
              sections.each(&:apply_log_entries!)

              @committed = true
              Petra.logger.info "Committed transaction #{@identifier}", :blue, :underline

              # Step 5: Wow, me made it this far!
              #   Now it's time to clean up and remove the data we previously persisted for this
              #   transaction before releasing the lock on all of the objects and the transaction itself.
              # TODO: See if this causes problems with other threads working on this transactions. Probably keep
              #   the entries around and just mark the transaction as committed?
              #   Idea: keep it and add a last log entry like `transaction_commit` and persist it.
              persistence_adapter.reset_transaction(self)
            end
          rescue Petra::ReadIntegrityError => e
            raise
            # One (or more) of the attributes from our read set changed externally
          rescue Petra::LockError => e
            raise
            # One (or more) of the objects could not be locked.
            #   The object locks are freed by itself, but we have to notify
            #   the outer application about this commit error
          end
        end
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
      # Tries to acquire locks on all of the given proxies and executes
      # the given block afterwards.
      #
      # Please note that the objects may still be altered outside of transactions.
      #
      # This ensures that all object locks are released if an exception occurs
      #
      # @param [Array<Petra::Proxies::ObjectProxy>] proxies
      #
      # @raise [Petra::LockError] If +suspend+ is set to +false+, a LockError is raised
      #   if one of the object locks could not be acquired
      #
      # TODO: Many objects, many SystemStackErrors?
      #
      def with_locked_objects(proxies, suspend: true, &block)
        if proxies.empty?
          block.call
        else
          persistence_adapter.with_object_lock(proxies.first, suspend: suspend) do
            with_locked_objects(proxies[1..-1], suspend: suspend, &block)
          end
        end
      end

      #
      # @return [Petra::PersistenceAdapters::Adapter] the current persistence adapter
      #
      def persistence_adapter
        Petra.transaction_manager.persistence_adapter
      end

    end
  end
end
