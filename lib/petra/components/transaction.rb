# frozen_string_literal: true

require 'petra/components/entry_set'
require 'petra/components/section'
require 'petra/components/proxy_cache'
require 'continuation'

module Petra
  module Components
    class Transaction
      include ActiveSupport::Callbacks

      attr_reader :identifier
      attr_reader :persisted
      attr_reader :committed
      attr_reader :reset

      alias persisted? persisted
      alias committed? committed
      alias reset? reset

      delegate :log_attribute_change,
               :log_object_persistence,
               :log_attribute_read,
               :log_object_initialization,
               :log_object_destruction, to: :current_section

      def initialize(identifier:)
        @identifier = identifier
        @persisted  = false
        @committed  = false
        @reset      = false
      end

      def after_initialize
        # Initialize the current section
        current_section
      end

      #----------------------------------------------------------------
      #                          Callbacks
      #----------------------------------------------------------------

      define_callbacks :commit, :rollback, :reset
      define_callbacks :persist

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
      # Checks whether the given attribute has been changed during the transaction.
      # It basically searches for a matching write set entry in all previous (and current) sections.
      # If such an entry exists AND there hasn't been an attribute change veto which is newer than it,
      # the attribute counts as "changed within the transaction".
      #
      # @return [Boolean] +true+ if there there was a valid attribute change
      #
      def attribute_value?(proxy, attribute:)
        sections.reverse.any? { |s| s.value_for?(proxy, attribute: attribute) } &&
            !attribute_change_veto?(proxy, attribute: attribute)
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
        sections
          .reverse.find { |s| s.read_value_for?(proxy, attribute: attribute) }
          .read_value_for(proxy, attribute: attribute)
      end

      alias attribute_changed? attribute_value?
      alias attribute_read? read_attribute_value?

      #
      # @return [Petra::Components::EntrySet] the combined log entries of all sections from old to new
      #
      # TODO: Cache entries from already persisted sections.
      #
      def log_entries
        sections.each_with_object(EntrySet.new) { |s, es| es.concat(s.log_entries) }
      end

      #
      # @param [Petra::Proxies::ObjectProxy] proxy
      #
      # @param [String, Symbol] attribute
      #
      # @param [Object] external_value
      #   The current external value. It is needed as read integrity overrides
      #   only stay active as long as the external value stays the same.
      #
      # @return [Boolean] +true+ if ReadIntegrityErrors should still be suppressed for
      #   the given attribute. This is the case if a ReadIntegrityOverride log entry is still
      #   active
      #
      def read_integrity_override?(proxy, attribute:, external_value:)
        # Step 1: Search for the latest read integrity override entry we have for the given attribute
        attribute_entries = log_entries.for_attribute_key(proxy.__attribute_key(attribute))
        rio_entry         = attribute_entries.of_kind(:read_integrity_override).latest

        # If there was no override in the past sections, there can't be an active one
        return false unless rio_entry

        # Step 2: Find the read log entry we previously created for this attribute.
        #   There has to be one as otherwise no read integrity error could have happened.
        read_entry = attribute_entries.of_kind(:attribute_read).latest

        # Step 3: Test if the read entry is newer than the RIO entry.
        #   If that's the case, the user most likely decided that the new external
        #   value should be displayed inside the transaction.
        #   As we could have only landed here if the external value changed again,
        #   we probably have to re-raise an exception about that.
        return false if read_entry > rio_entry

        # Step 4: We found ourselves a RIO entry that has not yet been invalidated
        #   by another attribute read, good.
        #   Now we have to check whether the current external value is still
        #   the same as at the time we generated the RIO entry.
        #   If that's the case, we still have an active read integrity override.
        rio_entry.external_value == external_value
      end

      #
      # @param [Petra::Proxies::ObjectProxy] proxy
      #
      # @param [String, Symbol] attribute
      #
      # @return [Boolean] +true+ if there is an active AttributeChangeVeto
      #   for the given attribute, meaning that all attribute changes
      #   should be discarded.
      #
      # TODO: Combine with #read_integrity_override, because DRY
      #
      def attribute_change_veto?(proxy, attribute:)
        # Step 1: Search for the latest attribute change veto entry we have for the given attribute
        attribute_entries = log_entries.for_attribute_key(proxy.__attribute_key(attribute))
        acv_entry         = attribute_entries.of_kind(:attribute_change_veto).latest

        # If there hasn't been an attribute change veto in the past, there can't be an active one
        return false unless acv_entry

        # Step 2: Find the latest attribute change entry we have for the given attribute
        change_entry = attribute_entries.of_kind(:attribute_change).latest

        # Step 3: Check if the change entry is newer than the ACV entry
        #   If so, the ACV entry is no longer valid
        change_entry < acv_entry
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
      # @raise [Petra::ReadIntegrityError] Raised if an attribute that we previously read,
      #   but NOT changed was changed externally
      #
      # @raise [Petra::ReadWriteIntegrityError] Raised if an attribute that we previously read AND
      #   changed was changed externally
      #
      def verify_attribute_integrity!(proxy, attribute:, force: false)
        # If we didn't read the attribute before, we can't search for changes
        return unless attribute_read?(proxy, attribute: attribute)

        # Don't perform the check if the force flag is not set and
        # petra is configured to not fail on read integrity errors at all.
        return if !force && !Petra.configuration.instant_read_integrity_fail

        # New objects won't be changed externally...
        return if proxy.__new?

        external_value  = proxy.unproxied.send(attribute)
        last_read_value = read_attribute_value(proxy, attribute: attribute)

        # If nothing changed, we're done
        return if external_value == last_read_value

        # The user has previously chosen to ignore the external changes to this attribute (using ignore!).
        # Therefore, we do not have to raise another exception
        # OR
        # We only read this attribute before.
        # If the user (/developer) previously placed a read integrity override
        # for the current external value, we don't have to re-raise an exception about the change
        return if read_integrity_override?(proxy, attribute: attribute, external_value: external_value)

        if attribute_changed?(proxy, attribute: attribute)
          # We read AND changed this attribute before

          # If there is already an active attribute change veto (meaning that we didn't change
          # the attribute again after the last one), we don't have to raise another exception about it.
          # TODO: This should have already been filtered out by #attribute_changed?
          # return if attribute_change_veto?(proxy, attribute: attribute)

          callcc do |continuation|
            exception = Petra::WriteClashError.new(attribute:      attribute,
                                                   object:         proxy,
                                                   our_value:      attribute_value(proxy, attribute: attribute),
                                                   external_value: external_value,
                                                   continuation:   continuation)

            fail exception, "The attribute `#{attribute}` has been changed externally and in the transaction."
          end
        else
          callcc do |continuation|
            exception = Petra::ReadIntegrityError.new(attribute:       attribute,
                                                      object:          proxy,
                                                      last_read_value: last_read_value,
                                                      external_value:  external_value,
                                                      continuation:    continuation)
            fail exception, "The attribute `#{attribute}` has been changed externally."
          end
        end
      end

      #----------------------------------------------------------------
      #                         Object Helpers
      #----------------------------------------------------------------

      def objects
        @objects ||= ProxyCache.new(self)
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
        @sections ||= begin
          persistence_adapter.with_transaction_lock(self) do
            persistence_adapter.savepoints(self).map do |savepoint|
              Petra::Components::Section.new(self, savepoint: savepoint)
            end.sort_by(&:savepoint_version)
          end
        end
      end

      #----------------------------------------------------------------
      #                        Transaction Handling
      #----------------------------------------------------------------

      #
      # Tries to commit the current transaction
      #
      def commit!
        run_callbacks :commit do
          begin
            # Step 1: Lock this transaction so no other thread may alter it any more
            persistence_adapter.with_transaction_lock(identifier) do

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
        run_callbacks :rollback do
          current_section.reset! unless current_section.persisted?
          Petra.logger.debug "Rolled back section #{current_section.savepoint}", :yellow
        end
      end

      #
      # Persists the current transaction section using the configured persistence adapter
      #
      def persist!
        run_callbacks :persist do
          current_section.enqueue_for_persisting!
          persistence_adapter.persist!
          Petra.logger.debug "Persisted transaction #{@identifier}", :green
          @persisted = true
        end
      end

      #
      # Completely dismisses the current transaction and removes it from the persistence storage
      #
      def reset!
        run_callbacks :reset do
          persistence_adapter.reset_transaction(self)
          @sections = []
          Petra.logger.warn "Reset transaction #{@identifier}", :red
        end
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
          yield
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
