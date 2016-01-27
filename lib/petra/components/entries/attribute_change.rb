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
          proxied_object.send(method, new_value)
        end

        Petra::Components::LogEntry.register_entry_type(:attribute_change, self)
      end
    end
  end
end


