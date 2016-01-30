module Petra
  module Components
    module Entries
      class ObjectPersistence < Petra::Components::LogEntry
        field_accessor :method

        def self.kind
          :object_persistence
        end

        def apply!
          proxied_object.send(method)
        end

        Petra::Components::LogEntry.register_entry_type(kind, self)
      end
    end
  end
end
