module Petra
  module Components
    class Section

      attr_reader :transaction
      attr_reader :savepoint

      def initialize(transaction, savepoint: nil)
        @transaction = transaction
        @savepoint   = savepoint || next_savepoint_name
      end

      #
      # @return [Fixnum] the savepoint's version number
      #
      def savepoint_version
        savepoint.split('/')[1].to_i
      end

      #----------------------------------------------------------------
      #                        Read / Write set
      #----------------------------------------------------------------

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
      def log_attribute_change(proxy, attribute:, old_value:, new_value:)
        return if old_value == new_value

        # Replace any existing value for the current attribute in the
        # memory write set with the new value
        add_to_write_set(proxy, attribute, new_value)

        Petra.log "Logged attribute change (#{old_value} => #{new_value})", :yellow
      end

      #
      # Logs the persistence of an object. This basically means that the attribute updates were
      # written to a shared memory. This might simply be the process memory for normal ruby objects,
      # but might also be a call to save() or update() for ActiveRecord::Base instances.
      #
      def log_object_persistence

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
      # Persists the current section
      # TODO: Only persist attribute changes for objects which called a persisting method.
      # TODO: To clarify: Only persist changes that happened before the persistence method was called.
      #
      def persist!

      end

      private

      #
      # Sets a new value for the given attribute in this section's write set
      #
      def add_to_write_set(proxy, attribute, value)
        write_set[proxy.__attribute_key(attribute)] = value
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