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
        write_set.has_key?(proxy.__attribute_key(attribute))
      end

      #----------------------------------------------------------------
      #                         Log Entries
      #----------------------------------------------------------------

      #
      # @return [Array<Petra::Components::LogEntry>]
      #
      def log_entries
        @log_entries ||= []
      end

      def log_entries_for(proxy)
        log_entries.select { |e| e.for_object?(proxy.__object_key) }
      end

      def log_entries_of_kind(kind)
        log_entries.select { |e| e.kind?(kind) }
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
        # Generate a read set entry when we attempt to change an attribute value for the first time.
        # This is necessary as real attribute reads are not necessarily performed in the same section
        # as attribute changes and persistence (e.g. #edit and #update in Rails)
        # This has to be done even if the attribute wasn't really changed as the user most likely
        # saw the current value and therefore decided not to change it.
        unless value_for?(proxy, attribute: attribute)
          log_attribute_read(proxy, attribute: attribute, new_value: old_value, method: method)
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

        Petra.log "Logged attribute change (#{old_value} => #{new_value})", :yellow
      end

      #
      # Generates a log entry for an attribute read in a certain object.
      #
      # @see #log_attribute_change for parameter details
      #
      # TODO: Notice attribute changes and throw an exception (if wished)
      #
      def log_attribute_read(proxy, attribute:, new_value:, method: nil)
        add_to_read_set(proxy, attribute, new_value)
        add_log_entry(proxy,
                      attribute: attribute,
                      method:    method,
                      kind:      'attribute_read',
                      new_value: new_value)

        Petra.log "Logged attribute read (#{attribute} => #{new_value})", :yellow
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
      def log_object_persistence(proxy, method: nil)
        # All log entries for the current object prior to this persisting method
        # have to be persisted as the object itself is.
        log_entries_for(proxy).each(&:mark_as_object_persisted!)

        # All attribute reads prior to this have to be persisted
        # as they might have had impact on the current object state.
        # This does not only include the current object, but everything that was
        # read until now!
        # TODO: Could this be more intelligent?
        log_entries_of_kind(:attribute_read).each(&:mark_as_object_persisted!)

        add_log_entry(proxy,
                      method:           method,
                      kind:             'object_persistence',
                      object_persisted: true)
      end

      #
      # Logs the destruction of an object.
      # Currently, this is only used with ActiveRecord::Base instances, but there might
      # be a way to handle GC with normal ruby objects (attach a handler to at least get notified).
      #
      def log_object_destruction

      end

      #----------------------------------------------------------------
      #                         Persistence
      #----------------------------------------------------------------

      #
      # Persists the current section (resp. enqueues it to be persisted)
      #
      def enqueue_for_persisting!
        log_entries.each(&:enqueue_for_persisting!)
      end

      private

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
      def add_log_entry(proxy, object_persisted: false, **options)
        attribute     = options.delete(:attribute)
        attribute_key = attribute && proxy.__attribute_key(attribute)

        entry = Petra::Components::LogEntry.new(self,
                                                transaction_identifier: transaction.identifier,
                                                savepoint:              savepoint,
                                                attribute_key:          attribute_key,
                                                object_key:             proxy.__object_key,
                                                object_persisted:       object_persisted,
                                                transaction_persisted:  persisted?,
                                                **options)

        Petra.log "Added log entry: #{transaction.identifier}/#{savepoint}/#{attribute_key}", :yellow

        log_entries << entry
      end

      #
      # In case the this section is not the latest one in the current transaction,
      # we have to load the steps previously done from the persistence value
      #
      # Also sets the `persisted?` flag depending on whether this section has
      # be previously persisted or not.
      #
      def load_persisted_log_entries
        @log_entries = Petra.transaction_manager.persistence_adapter.log_entries(self)
        @log_entries.each do |entry|
          write_set[entry.attribute_key] = entry.new_value if entry.attribute_change?
          read_set[entry.attribute_key] = entry.new_value if entry.attribute_read?
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
        if transaction.sections.empty?
          version = 1
        else
          version = transaction.sections.last.savepoint_version + 1
        end

        [transaction.identifier, version.to_s].join('/')
      end

    end
  end
end
