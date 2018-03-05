# frozen_string_literal: true

module Petra
  module Components
    module Entries
      #
      # Tells the system to ignore all attribute changes we made to the current
      # attribute during the transaction.
      #
      class AttributeChangeVeto < Petra::Components::LogEntry
        # Mostly for debugging purposes: The external value that caused
        # the creation of this log entry
        field_accessor :external_value

        def self.kind
          :attribute_change_veto
        end

        #
        # As for ReadIntegrityOverrides, we have to make sure that
        # AttributeChangeVetoes are always persisted.
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
