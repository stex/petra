# frozen_string_literal: true
module Petra
  module Components
    module Entries
      #
      # Tells the system not to raise further ReadIntegrityErrors for the given attribute
      # as long as the external value stays the same.
      #
      class ReadIntegrityOverride < Petra::Components::LogEntry
        # The external attribute value at the time this log entry
        # was created. It is used to determine whether a new ReadIntegrityError has
        # to be raised or not.
        field_accessor :external_value

        def self.kind
          :read_integrity_override
        end

        #
        # ReadIntegrityOverrides always have to be persisted:
        # They are only generated if an exception (ReadIntegrityError, etc) happened
        # which in most cases (except for a rescue within the transaction proc itself)
        # means that its execution stopped and the only thing left is persisting the transaction.
        # Therefore, this log entry will most likely be the last one in the current section
        # and would be lost if we wouldn't persist it.
        #
        def persist?
          true
        end

        def apply!; end

        Petra::Components::LogEntry.register_entry_type(kind, self)
      end
    end
  end
end
