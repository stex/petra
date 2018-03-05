# frozen_string_literal: true
module Petra
  module Components
    module Entries
      class AttributeRead < Petra::Components::LogEntry
        field_accessor :method
        field_accessor :value

        def self.kind
          :attribute_read
        end

        def apply!; end

        Petra::Components::LogEntry.register_entry_type(:attribute_read, self)
      end
    end
  end
end
