# frozen_string_literal: true
module Petra
  module Components
    module Entries
      class ObjectPersistence < Petra::Components::LogEntry
        field_accessor :method

        # Arguments given to the persistence method.
        # This is especially necessary for persistence methods which are
        # also attribute writers or similar.
        field_accessor :args

        def self.kind
          :object_persistence
        end

        def apply!
          proxied_object.send(method, *(args || []))
        end

        Petra::Components::LogEntry.register_entry_type(kind, self)
      end
    end
  end
end
