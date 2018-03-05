# frozen_string_literal: true

require 'petra/util/field_accessors'
require 'petra/util/registrable'

module Petra
  module Components
    #
    # A log entry is basically a struct with certain helper functions.
    # This class contains some base functionality and a map of more specific log entry types.
    #
    # Registered entry types may define own +field_accessors+ which will be
    # serialized when persisting the log entries.
    #
    class LogEntry
      include Comparable
      include Petra::Util::Registrable
      include Petra::Util::FieldAccessors

      acts_as_register :entry_type

      field_accessor :savepoint
      field_accessor :transaction_identifier

      # Identifier usually used to persist the current entry.
      # It is set by the used persistence adapter.
      field_accessor :entry_identifier

      # An object is a 'new object' if it was created during this transaction and does
      # not exist outside of it yet. This information is necessary when restoring
      # proxies from previous sections
      field_accessor :new_object

      # Identifies the object the changes were performed on,
      # e.g. "User", 1 for @user.save
      # The object class is also needed to load the corresponding class configuration
      attr_reader :object_class
      attr_reader :attribute

      field_accessor :object_key
      field_accessor :attribute_key

      # Means that the client persisted the object referenced by this log entry, e.g. through #save in case of AR
      attr_accessor :object_persisted

      # Means that the log entry was actually persisted within the transaction
      attr_accessor :transaction_persisted

      attr_reader :section

      alias object_persisted? object_persisted
      alias transaction_persisted? transaction_persisted
      alias new_object? new_object

      def self.log!(kind, section:, **fields)
        fail ArgumentError, "#{kind} is not a valid entry type" unless registered_entry_type?(kind)
        registered_entry_type(kind).new(section, **fields)
      end

      #
      # Initializes a new log entry based on the given section and options
      #
      # @param [Hash] fields
      # @option options [String] :savepoint (section.savepoint)
      #   The savepoint name this log entry is part of.
      #
      # @option options [String] :transaction_identifier (section.transaction.identifier)
      #   The entry's transaction's identifier
      #
      # @option options [String, Symbol] :method
      #   The method which caused this log entry.
      #   In some cases, it makes sense to specify a different method here as
      #   this value is used when actually applying the log entry (see Petra::Proxies::ActiveRecordProxy)
      #
      # @option options [String] attribute_key
      #   The unique key for the attribute which was altered/read in this log entry.
      #   Only available for attribute_read/attribute_change entries
      #
      # @option options [String] object_key
      #   The unique key for the object/proxy which caused this log entry.
      #   The internal values for @object_class and @object_id are automatically set based on it.
      #
      # @option options [String] kind
      #   The entry's kind, e.g. 'object_initialization'
      #
      # @option options [String] old_value
      # @option options [String] new_value
      #
      def initialize(section, **fields)
        @section = section

        @object_persisted      = fields.delete(:object_persisted)
        @transaction_persisted = fields.delete(:transaction_persisted)

        # Restore the given field accessors
        fields.each do |k, v|
          send("#{k}=", v)
        end

        self.savepoint              ||= section.savepoint
        self.transaction_identifier ||= section.transaction.identifier
      end

      #
      # If both entries were made in the same section, the smaller entry was
      # generated earlier than the other.
      # If both entries are in different sections, the one with a smaller
      # savepoint version is considered smaller.
      #
      def <=>(other)
        if section == other.section
          section.log_entries.index(self) <=> section.log_entries.index(other)
        else
          section.savepoint_version <=> other.section.savepoint_version
        end
      end

      #----------------------------------------------------------------
      #                     Internal Field Handling
      #----------------------------------------------------------------

      def attribute_change?
        kind?(:attribute_change)
      end

      def attribute_read?
        kind?(:attribute_read)
      end

      def object_persistence?
        kind?(:object_persistence)
      end

      def object_initialization?
        kind?(:object_initialization)
      end

      def mark_as_object_persisted!
        @object_persisted = true
      end

      def mark_as_persisted!(identifier)
        @transaction_persisted = true
        @entry_identifier      = identifier
      end

      #
      # @return [Boolean] +true+ if this log entry should be destroyed
      #   if it is enqueued for the next persisting phase
      #
      def marked_for_destruction?
        !!@marked_for_destruction
      end

      #
      # @return [Hash] the necessary information about this entry to reproduce it later
      #   The result is mainly used when serializing the step later.
      #
      # @param [Hash] options
      #
      # @option options [String] :entry_identifier
      #   A section-unique identifier for the current log entry.
      #   It is usually given by the used persistence adapter.
      #
      # Information about the object / transaction persistence is not kept as this method
      # will only be used during persistence or on already persisted entries
      #
      def to_h(**options)
        fields.each_with_object(options.merge('kind' => self.class.kind)) do |(k, v), h|
          h[k] = v unless v.nil?
        end
      end

      #
      # Builds a log entry from the given section and hash, but automatically sets the persistence flags
      #
      # @return [Petra::Components::LogEntry]
      #
      def self.from_hash(section, fields)
        log!(fields.delete('kind'),
             section: section,
             object_persisted: true,
             transaction_persisted: true,
             **fields.symbolize_keys)
      end

      #
      # @return [Boolean] +true+ if this log entry was made in the context of the given object (key)
      #
      def for_object?(object_key)
        self.object_key == object_key
      end

      #
      # @return [Boolean] +true+ if this log entry is of the given kind
      #
      def kind?(kind)
        self.class.kind.to_s == kind.to_s
      end

      #----------------------------------------------------------------
      #                        Persistence
      #----------------------------------------------------------------

      #
      # Adds the log entry to the persistence queue if the following conditions are met:
      #
      # 1. The log entry has to be marked as 'object_persisted', meaning that the object was saved
      #    during/after the action which created the the entry
      # 2. The log entry hasn't been persisted previously
      #
      # This does not automatically mark this log entry as persisted,
      # this is done once the persistence adapter finished its work
      #
      def enqueue_for_persisting!
        return if transaction_persisted?
        return unless persist?
        Petra.transaction_manager.persistence_adapter.enqueue(self)
      end

      #
      # May be overridden by more specialized log entries,
      # the basic version will persist an entry as long as it is marked
      # as object persisted
      #
      def persist?
        object_persisted?
      end

      #----------------------------------------------------------------
      #                           Commit
      #----------------------------------------------------------------

      #
      # Applies the action performed in the current log entry
      # to the corresponding object
      #
      def apply!
        not_implemented # nop?
      end

      #
      # Tries to undo a previously done #apply!
      # This is currently only possible for attribute changes as we do not know
      # how to undo destruction / persistence for general objects
      #
      def undo!
        load_proxy.send(:__undo_application__, self)
      end

      #----------------------------------------------------------------
      #                        Object Helpers
      #----------------------------------------------------------------

      #
      # @return [Petra::Proxies::ObjectProxy] the proxy this log entry was made for
      #
      def load_proxy
        @load_proxy ||= transaction.objects.fetch(object_key) do
          new_object? ? initialize_proxy : restore_proxy
        end
      end

      def to_s
        "#{section.savepoint}/#{@object_id} => #{self.class.kind}"
      end

      protected

      def proxied_object
        load_proxy.send(:proxied_object)
      end

      #
      # Initializes a proxy for the object which was initialized in this log entry.
      # This is done by initializing a new object and set the old generated object_id for its proxy
      #
      # @return [Petra::Proxies::ObjectProxy] a proxy for a clean object (no attributes set).
      #   Every attribute value is taken from its write set.
      #
      def initialize_proxy
        klass    = object_class.constantize
        instance = configurator.__inherited_value(:init_method, proc_expected: true, base: klass)
        Petra::Proxies::ObjectProxy.for(instance, object_id: @object_id)
      end

      #
      # Loads an object which most likely existed outside of the transaction
      # and wraps it in a proxy.
      #
      # @return [Petra::Proxies::ObjectProxy] a proxy for the object this log entry is about.
      #
      # Please note that no custom attributes are set, they will be served from the write set.
      #
      # TODO: Raise an exception here if a proxy could not be restored.
      #   This most likely means that the object was destroyed outside of the transaction!
      #
      def restore_proxy
        klass    = object_class.constantize
        instance = configurator.__inherited_value(:lookup_method, @object_id, proc_expected: true, base: klass)
        Petra::Proxies::ObjectProxy.for(instance)
      end

      def object_key=(key)
        self[:object_key]         = key
        @object_class, @object_id = key.split('/') if key
      end

      def attribute_key=(key)
        self[:attribute_key] = key
        @object_class, @object_id, @attribute = key.split('/') if key
      end

      def configurator
        @configurator ||= Petra.configuration[object_class]
      end

      def transaction
        Petra.current_transaction
      end

      #
      # Ensures that the currently set log entry kind is actually one of the valid ones
      #
      def validate_kind!
        return if Petra::Components::LogEntry.registered_entry_type?(kind)
        fail ArgumentError, "#{kind} is not a valid log entry kind."
      end
    end
  end
end
