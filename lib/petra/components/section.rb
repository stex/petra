# frozen_string_literal: true

module Petra
  module Components
    class Section

      attr_reader :transaction
      attr_reader :savepoint

      def initialize(transaction, savepoint: nil)
        @transaction = transaction
        @savepoint   = savepoint || next_savepoint_name
        load_persisted_log_entries
      end

      #
      # @return [Fixnum] the savepoint's version number
      #
      def savepoint_version
        savepoint.split('/')[1].to_i
      end

      def persisted?
        !!@persisted
      end

      #----------------------------------------------------------------
      #                        Read / Write set
      #----------------------------------------------------------------

      #
      # Holds the values which were last read from attribute readers
      #
      def read_set
        @read_set ||= {}
      end

      #
      # The write set in a section only holds the latest value for each
      # attribute/object combination. The change history is done using log entries.
      # Therefore, the write set is a simple hash mapping object-attribute-keys to their latest value.
      #
      def write_set
        @write_set ||= {}
      end

      #
      # Holds all read integrity overrides which were generated during this section.
      # There should normally only be one per section.
      #
      # The hash maps attribute keys to the external value at the time the corresponding
      # log entry was generated. Please take a look at Petra::Components::Entries::ReadIntegrityOverride
      # for more information about this kind of log entry.
      #
      def read_integrity_overrides
        @read_integrity_overrides ||= {}
      end

      #
      # Holds all attribute change vetoes for the current section.
      # If an attribute key is in this hash, it means that all previous changes
      # made to it should be voided.
      #
      # If an attribute is changed again after a veto was added, it is removed from
      # this hash.
      #
      def attribute_change_vetoes
        @attribute_change_vetoes ||= {}
      end

      #
      # @return [Object, NilClass] the value which was set for the given attribute
      #   during this session. Please note that setting attributes to +nil+ is normal behaviour,
      #   so please make sure you always check whether there actually is value in the write set
      #   using #value_for?
      #
      def value_for(proxy, attribute:)
        write_set[proxy.__attribute_key(attribute)]
      end

      #
      # @return [Boolean] +true+ if this section's write set contains a value
      #   for the given attribute (if a new value was set during this section)
      #
      def value_for?(proxy, attribute:)
        write_set.key?(proxy.__attribute_key(attribute))
      end

      #
      # @return [Boolean] +true+ if a new object attribute with the given name
      #   was read during this section. Each attribute is only put into the read set once - except
      #   for when the read value wasn't used afterwards (no persistence)
      #
      def read_value_for?(proxy, attribute:)
        read_set.key?(proxy.__attribute_key(attribute))
      end

      #
      # @return [Object, NilClass] the attribute value which was read from the original object
      #   during this section or +nil+. Please check whether the attribute was read at all during
      #   this section using #read_value_for?
      #
      def read_value_for(proxy, attribute:)
        read_set[proxy.__attribute_key(attribute)]
      end

      #
      # @return [Boolean] +true+ if there is a read integrity override for
      #   the given attribute name
      #
      def read_integrity_override?(proxy, attribute:)
        read_integrity_overrides.key?(proxy.__attribute_key(attribute))
      end

      #
      # @return [Object] The external value at the time the requested
      #   read integrity override was placed.
      #
      def read_integrity_override(proxy, attribute:)
        read_integrity_overrides[proxy.__attribute_key(attribute)]
      end

      #----------------------------------------------------------------
      #                         Log Entries
      #----------------------------------------------------------------

      #
      # @return [Petra::Components::EntrySet]
      #
      def log_entries
        @log_entries ||= EntrySet.new
      end

      #
      # Generates a log entry for an attribute change in a certain object.
      # If old and new value are the same, no log entry is created.
      #
      # @param [Petra::Components::ObjectProxy] proxy
      #   The proxy which received the method call to change the attribute
      #
      # @param [String, Symbol] attribute
      #   The name of the attribute which was changed
      #
      # @param [Object] old_value
      #   The attribute's value before the change
      #
      # @param [Object] new_value
      #   The attribute's new value
      #
      # @param [String, Symbol] method
      #   The method which was used to change the attribute
      #
      def log_attribute_change(proxy, attribute:, old_value:, new_value:, method: nil)
        # Generate a read set entry if we didn't read this attribute before.
        # This is necessary as real attribute reads are not necessarily performed in the same section
        # as attribute changes and persistence (e.g. #edit and #update in Rails)
        # This has to be done even if the attribute wasn't really changed as the user most likely
        # saw the current value and therefore decided not to change it.
        unless transaction.read_attribute_value?(proxy, attribute: attribute)
          log_attribute_read(proxy, attribute: attribute, value: old_value, method: method)
        end

        return if old_value == new_value

        # Replace any existing value for the current attribute in the
        # memory write set with the new value
        add_to_write_set(proxy, attribute, new_value)
        add_log_entry(proxy,
                      attribute: attribute,
                      method:    method,
                      kind:      'attribute_change',
                      old_value: old_value,
                      new_value: new_value)

        Petra.logger.info "Logged attribute change (#{old_value} => #{new_value})", :yellow
      end

      #
      # Generates a log entry for an attribute read in a certain object.
      #
      # @see #log_attribute_change for parameter details
      #
      def log_attribute_read(proxy, attribute:, value:, method: nil, **options)
        add_to_read_set(proxy, attribute, value)
        add_log_entry(proxy,
                      attribute: attribute,
                      method:    method,
                      kind:      'attribute_read',
                      value:     value,
                      **options)

        Petra.logger.info "Logged attribute read (#{attribute} => #{value})", :yellow
        true
      end

      #
      # Logs the initialization of an object
      #
      def log_object_initialization(proxy, method: nil)
        # Mark this object as recently initialized
        recently_initialized_object!(proxy)

        add_log_entry(proxy,
                      kind:   'object_initialization',
                      method: method)
        true
      end

      #
      # Logs the persistence of an object. This basically means that the attribute updates were
      # written to a shared memory. This might simply be the process memory for normal ruby objects,
      # but might also be a call to save() or update() for ActiveRecord::Base instances.
      #
      # @param [Petra::Components::ObjectProxy] proxy
      #   The proxy which received the method call
      #
      # @param [String, Symbol] method
      #   The method which caused the persistence change
      #
      def log_object_persistence(proxy, method: nil, args: [])
        # All log entries for the current object prior to this persisting method
        # have to be persisted as the object itself is.
        # This includes the object initialization log entry
        log_entries.for_proxy(proxy).each(&:mark_as_object_persisted!)

        # All attribute reads prior to this have to be persisted
        # as they might have had impact on the current object state.
        # This does not only include the current object, but everything that was
        # read until now!
        # TODO: Could this be more intelligent?
        log_entries.of_kind(:attribute_read).each(&:mark_as_object_persisted!)

        add_log_entry(proxy,
                      method:           method,
                      kind:             'object_persistence',
                      object_persisted: true,
                      args:             args)

        true
      end

      #
      # Logs the destruction of an object.
      # Currently, this is only used with ActiveRecord::Base instances, but there might
      # be a way to handle GC with normal ruby objects (attach a handler to at least get notified).
      #
      def log_object_destruction(proxy, method: nil)
        # Destruction is a form of persistence, resp. its opposite.
        # Therefore, we have to make sure that any other log entries for this
        # object will be transaction persisted as the may have lead to the object's destruction.
        #
        # Currently, this happens even if the object hasn't been persisted prior to
        # its destruction which is accepted behaviour e.g. by ActiveRecord instances.
        # We'll have to see if this should stay the common behaviour.
        log_entries.for_proxy(proxy).each(&:mark_as_object_persisted!)

        # As for attribute persistence, every attribute which was read in the current section
        # might have had impact on the destruction of this object. Therefore, we have
        # to make sure that all these log entries will be persisted.
        log_entries.of_kind(:attribute_read).each(&:mark_as_object_persisted!)

        add_log_entry(proxy,
                      kind:             'object_destruction',
                      method:           method,
                      object_persisted: true)
        true
      end

      #
      # Logs the fact that the user decided to ignore further ReadIntegrityErrors
      # on the given attribute as long as its external value stays the same.
      #
      # @param [Boolean] update_value
      #   If +true+, a new read set entry is generated along with the RIO one.
      #   This will cause the transaction to display the new external value instead of the
      #   one we last read and will also automatically invalidate the RIO entry which
      #   is only kept to have the whole transaction time line.
      #
      def log_read_integrity_override(proxy, attribute:, external_value:, update_value: false)
        add_log_entry(proxy,
                      kind:           'read_integrity_override',
                      attribute:      attribute,
                      external_value: external_value)

        # If requested, add a new read log entry for the new external value
        log_attribute_read(proxy, attribute: attribute, value: external_value, persist_on_retry: true) if update_value
      end

      #
      # Logs the fact that the user decided to "undo" all previous changes
      # made to the given attribute
      #
      def log_attribute_change_veto(proxy, attribute:, external_value:)
        add_log_entry(proxy,
                      kind:           'attribute_change_veto',
                      attribute:      attribute,
                      external_value: external_value)

        # Also log the current external attribute value, so the transaction uses the newest available one
        log_attribute_read(proxy, attribute: attribute, value: external_value, persist_on_retry: true)
      end

      #----------------------------------------------------------------
      #                        Object Handling
      #----------------------------------------------------------------

      #
      # As objects which were initialized inside a transaction receive
      # a temporary ID whose generation again requires knowledge about
      # their membership regarding the below object sets leading to an
      # infinite loop, we have to keep a temporary list of object ids (ruby)
      # until they received their transaction object id
      #
      def recently_initialized_objects
        @recently_initialized_objects ||= []
      end

      def recently_initialized_object!(proxy)
        recently_initialized_objects << proxy.send(:proxied_object).object_id
      end

      def recently_initialized_object?(proxy)
        recently_initialized_objects.include?(proxy.send(:proxied_object).object_id)
      end

      #
      # @return [Hash<Petra::Proxies::ObjectProxy, Array<String,Symbol>>]
      #   All attributes which were read during this section grouped by the objects (proxies)
      #   they belong to.
      #
      # Only entries which were previously marked as object persisted are taken into account.
      #
      def read_attributes
        cache_if_persisted(:read_attributes) do
          log_entries.of_kind(:attribute_read).object_persisted.each_with_object({}) do |entry, h|
            h[entry.load_proxy] ||= []
            h[entry.load_proxy] << entry.attribute unless h[entry.load_proxy].include?(entry.attribute)
          end
        end
      end

      #
      # @return [Array<Petra::Proxies::ObjectProxy>] All Objects that were part of this section.
      #   Only log entries marked as object persisted are taken into account
      #
      def objects
        cache_if_persisted(:all_objects) do
          log_entries.object_persisted.map(&:load_proxy).uniq
        end
      end

      #
      # @return [Array<Petra::Proxies::ObjectProxy>] Objects that were read during this section
      #   Only read log entries which were marked as object persisted are taken into account
      #
      def read_objects
        cache_if_persisted(:read_objects) do
          read_attributes.keys
        end
      end

      #
      # @return [Array<Petra::Proxies::ObjectProxy>] Objects that were created during this section.
      #
      # It does not matter whether the section was persisted or not in this case,
      # the only condition is that the object was "object_persisted" after its initialization
      #
      def created_objects
        cache_if_persisted(:created_objects) do
          log_entries.of_kind(:object_initialization).object_persisted.map(&:load_proxy).uniq
        end
      end

      #
      # @return [Array<Petra::Proxies::ObjectProxy>] Objects which were initialized, but not
      #   yet persisted during this section. This may only be the case for the current section
      #
      def initialized_objects
        cache_if_persisted(:initialized_objects) do
          log_entries.of_kind(:object_initialization).not_object_persisted.map(&:load_proxy).uniq
        end
      end

      #
      # @see #created_objects
      #
      # This method will also return objects which were not yet `object_persisted`, e.g.
      # to be used during the current transaction section
      #
      def initialized_or_created_objects
        cache_if_persisted(:initialized_or_created_objects) do
          (initialized_objects + created_objects).uniq
        end
      end

      #
      # @return [Array<Petra::Proxies::ObjectProxies>] Objects which were destroyed
      #   during the current section
      #
      def destroyed_objects
        cache_if_persisted(:destroyed_objects) do
          log_entries.of_kind(:object_destruction).map(&:load_proxy).uniq
        end
      end

      #----------------------------------------------------------------
      #                         Persistence
      #----------------------------------------------------------------

      #
      # Removes all log entries and empties the read and write set.
      # This should only be done on the current section and as long as the log
      # entries haven't been persisted.
      #
      def reset!
        fail Petra::PetraError, 'An already persisted section may not be reset' if persisted?
        @log_entries = []
        @read_set    = []
        @write_set   = []
      end

      def prepare_for_retry!
        log_entries.prepare_for_retry!
      end

      #
      # @see Petra::Components::EntrySet#apply
      #
      def apply_log_entries!
        log_entries.apply!
      end

      #
      # @see Petra::Components::EntrySet#enqueue_for_persisting!
      #
      def enqueue_for_persisting!
        log_entries.enqueue_for_persisting!
        @persisted = true
      end

      private

      #
      # Executes the block and caches its result if the current section has already
      # been persisted (= won't change any more)
      #
      def cache_if_persisted(name)
        @cache ||= {}
        return (@cache[name.to_s] ||= yield) if persisted?
        yield
      end

      #
      # Adds a new log entry to the current section.
      # New log entries are not automatically persisted, this is done through #enqueue_for_persisting!
      #
      # @param [Petra::Components::ObjectProxy] proxy
      #
      # @param [Boolean] object_persisted
      #
      # @param [Hash] options
      #
      def add_log_entry(proxy, kind:, object_persisted: false, **options)
        attribute     = options.delete(:attribute)
        attribute_key = attribute && proxy.__attribute_key(attribute)

        Petra::Components::LogEntry.log!(kind,
                                         section:                self,
                                         transaction_identifier: transaction.identifier,
                                         savepoint:              savepoint,
                                         attribute_key:          attribute_key,
                                         object_key:             proxy.__object_key,
                                         object_persisted:       object_persisted,
                                         transaction_persisted:  persisted?,
                                         new_object:             proxy.__new?,
                                         **options).tap do |entry|
          Petra.logger.debug "Added Log Entry: #{entry}", :yellow
          log_entries << entry
        end
      end

      #
      # In case the this section is not the latest one in the current transaction,
      # we have to load the steps previously done from the persistence value
      #
      # Also sets the `persisted?` flag depending on whether this section has
      # be previously persisted or not.
      #
      def load_persisted_log_entries
        @log_entries = EntrySet.new(Petra.transaction_manager.persistence_adapter.log_entries(self))
        @log_entries.each do |entry|
          if entry.kind?(:attribute_change)
            write_set[entry.attribute_key] = entry.new_value
          elsif entry.kind?(:attribute_read)
            read_set[entry.attribute_key] = entry.value
          elsif entry.kind?(:read_integrity_override)
            read_integrity_overrides[entry.attribute_key] = entry.external_value
          elsif entry.kind?(:attribute_change_veto)
            attribute_change_vetoes[entry.attribute_key] = entry.external_value
            # Remove any value changes done to the attribute previously in this section
            # This will speed up finding active attribute change vetoes as
            # the search is already canceled if no write set entry exists.
            write_set.delete(entry.attribute_key)
          end
        end

        @persisted = @log_entries.any?
      end

      def proxied_object(proxy)
        proxy.send(:proxied_object)
      end

      #
      # Sets a new value for the given attribute in this section's write set
      #
      def add_to_write_set(proxy, attribute, value)
        write_set[proxy.__attribute_key(attribute)] = value
      end

      #
      # @see #add_to_write_set
      #
      def add_to_read_set(proxy, attribute, value)
        read_set[proxy.__attribute_key(attribute)] = value
      end

      #
      # Builds the next savepoint name based on the transaction identifier and a version number
      #
      def next_savepoint_name
        version = if transaction.sections.empty?
                    1
                  else
                    transaction.sections.last.savepoint_version + 1
                  end

        [transaction.identifier, version.to_s].join('/')
      end

    end
  end
end
