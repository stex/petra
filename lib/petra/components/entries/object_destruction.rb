# frozen_string_literal: true
module Petra
  module Components
    module Entries
      class ObjectDestruction < Petra::Components::LogEntry
        field_accessor :method

        def self.kind
          :object_destruction
        end

        def apply!
          # TODO: React to `false` responses from destruction methods?
          proxied_object.send(method)
        end

        Petra::Components::LogEntry.register_entry_type(:object_destruction, self)
      end
    end
  end
end
