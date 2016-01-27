module Petra
  module Components
    module Entries
      class ObjectInitialization < Petra::Components::LogEntry
        field_accessor :method

        def self.kind
          :object_initialization
        end

        def apply!; end

        Petra::Components::LogEntry.register_entry_type(kind, self)
      end
    end
  end
end
