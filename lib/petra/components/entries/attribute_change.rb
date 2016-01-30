module Petra
  module Components
    module Entries
      class AttributeChange < Petra::Components::LogEntry
        field_accessor :old_value
        field_accessor :new_value
        field_accessor :method

        def self.kind
          :attribute_change
        end

        def apply!
          # Check if there is an an attribute change veto which is newer than this
          # attribute change. If there is, we may not apply this entry.
          # TODO: Check if this behaviour is sufficient.
          return if transaction.attribute_change_veto?(load_proxy, attribute: attribute)

          # Otherwise, use the logged method to set the new attribute value
          proxied_object.send(method, new_value)
        end

        Petra::Components::LogEntry.register_entry_type(:attribute_change, self)
      end
    end
  end
end


