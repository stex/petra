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

      attr_accessor :savepoint
      attr_accessor :transaction_identifier

      # The method which was used to perform the changes, e.g. "save"
      attr_accessor :method

      # Identifies the object the changes were performed on,
      # e.g. "User", 1 for @user.save
      attr_accessor :object_class
      attr_accessor :object_id

      def initialize(**options)

      end

    end
  end
end
