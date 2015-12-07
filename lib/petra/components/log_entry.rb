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

      def initialize(**options)

      end

    end
  end
end
