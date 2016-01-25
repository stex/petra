module Petra
  module Components
    #
    # Necessary Components:
    #
    #   - A transaction identifier (to find out which transaction a log entry belongs to)
    #   - A section identifier / savepoint name so we are able to undo log entries for a certain section
    #   - Type of the performed action (?)
    #   - Changeset (serialized?)
    #
    class LogEntry

      attr_accessor :savepoint
      attr_accessor :transaction_identifier

      # An object is a 'new object' if it was created during this transaction and does
      # not exist outside of it yet. This information is necessary when restoring
      # proxies from previous sections
      attr_reader :new_object

      # The method which was used to perform the changes, e.g. "save"
      # This is mainly used for debugging purposes and does not have to be set
      attr_accessor :method

      # The kind of action which was performed in this step, e.g. 'persistence' or 'attribute_change'
      attr_accessor :kind

      # Identifies the object the changes were performed on,
      # e.g. "User", 1 for @user.save
      # The object class is also needed to load the corresponding class configuration
      attr_reader :object_class
      attr_reader :object_id
      attr_reader :attribute

      attr_reader :object_key
      attr_reader :attribute_key

      attr_accessor :old_value
      attr_accessor :new_value

      # Means that the client persisted the object referenced by this log entry, e.g. through #save in case of AR
      attr_reader :object_persisted

      # Means that the log entry was actually persisted within the transaction
      attr_reader :transaction_persisted

      attr_reader :section

      alias_method :object_persisted?, :object_persisted
      alias_method :transaction_persisted?, :transaction_persisted
      alias_method :new_object?, :new_object

      def initialize(section, **options)
        @section                    = section
        self.savepoint              = options[:savepoint] || section.savepoint
        self.transaction_identifier = options[:transaction_identifier] || section.transaction.identifier
        self.method                 = options[:method]
        self.kind                   = options[:kind]
        self.attribute_key          = options[:attribute_key]
        self.object_key             = options[:object_key,]
        self.old_value              = options[:old_value]
        self.new_value              = options[:new_value]
        @new_object                 = options[:new_object]
        @object_persisted           = options[:object_persisted]
        @transaction_persisted      = options[:transaction_persisted]
      end

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

      def mark_as_persisted!
        @transaction_persisted = true
      end

      #
      # @return [Hash] the necessary information about this entry to reproduce it later
      #   The result is mainly used when serializing the step later.
      #
      # Information about the object / transaction persistence is not kept as this method
      # will only be used during persistence or on already persisted entries
      #
      def to_h
        [:new_object, :method, :kind, :attribute_key,
         :object_key, :old_value, :new_value].each_with_object({}) do |k, h|
          h[k] = send(k)
        end
      end

      #
      # Builds a log entry from the given section and hash, but automatically sets the persistence flags
      #
      # @return [Petra::Components::LogEntry]
      #
      def self.from_hash(section, hash)
        self.new(section, hash.merge(object_persisted: true, transaction_persisted: true))
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
        self.kind.to_s == kind.to_s
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
        return unless object_persisted?
        Petra.transaction_manager.persistence_adapter.enqueue(self)
      end

      #----------------------------------------------------------------
      #                           Commit
      #----------------------------------------------------------------

      #
      # Applies the action performed in the current log entry
      # to the corresponding object
      #
      def apply!
        load_proxy.send(:__apply__, self)
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
        @proxy ||= transaction.objects.fetch(object_key) do
          new_object? ? initialize_proxy : restore_proxy
        end
      end

      def to_s
        "#{section.savepoint}/#{object_id} => #{kind}"
      end

      private

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
        Petra::Proxies::ObjectProxy.for(instance, object_id: object_id)
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
        instance = configurator.__inherited_value(:lookup_method, object_id, proc_expected: true, base: klass)
        Petra::Proxies::ObjectProxy.for(instance)
      end

      def object_key=(key)
        @object_key               = key
        @object_class, @object_id = @object_key.split('/')
      end

      def attribute_key=(key)
        @attribute_key                        = key
        @object_class, @object_id, @attribute = @attribute_key.split('/') if @attribute_key
      end

      def configurator
        @configurator ||= Petra.configuration[object_class]
      end

      def transaction
        Petra.current_transaction
      end
    end
  end
end
