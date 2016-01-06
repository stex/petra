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

      def initialize(section, **options)
        @section                    = section
        self.savepoint              = options[:savepoint]
        self.transaction_identifier = options[:transaction_identifier]
        self.method                 = options[:method]
        self.kind                   = options[:kind]
        self.attribute_key          = options[:attribute_key]
        self.object_key             = options[:object_key,]
        self.old_value              = options[:old_value]
        self.new_value              = options[:new_value]
        @object_persisted           = options[:object_persisted]
        @transaction_persisted      = options[:transaction_persisted]
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
        [:method, :kind, :attribute_key, :object_key, :old_value, :new_value].each_with_object({}) do |k, h|
          h[k] = send(k)
        end
      end

      #
      # @return [Boolean] +true+ if this log entry was made in the context of the given object (key)
      #
      def for_object?(object_key)
        self.object_key == object_key
      end

      #
      # Adds the log entry to the persistence queue if the two following conditions are met:
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

      private

      def object_key=(key)
        @object_key               = key
        @object_class, @object_id = @object_key.split('/')
      end

      def attribute_key=(key)
        @attribute_key                        = key
        @object_class, @object_id, @attribute = @attribute_key.split('/') if @attribute_key
      end
    end
  end
end
