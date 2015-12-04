module Petra
  module PersistenceAdapters

    #
    # This class acts as an interface and specifies the methods that
    # a transaction adapter has to implement.
    #
    class Adapter

      def initialize(transaction_id:)
        @transaction_id = transaction_id
      end

      #
      # Persists the current transaction section.
      # This usually happens after executing the block given to Petra::Transaction.start
      #
      def persist_section!
        not_implemented
      end

      def add_to_read_set

      end

      def add_to_write_set

      end

    end
  end
end