module Petra
  module PersistenceAdapters

    #
    # This class acts as an interface and specifies the methods that
    # a transaction adapter has to implement.
    #
    class Adapter

      #
      # Persists the transaction steps which happened after
      # the last changes were persisted.
      #
      def persist
        not_implemented
      end

      #
      # @param [Petra::Components::Transaction]_transaction
      #   The transaction who's sections should be loaded
      #
      # @return [Array<Petra::Components::Section>] all already persisted sections
      #   for the given transaction id
      #
      def load_sections(_transaction)
        not_implemented
      end

      #
      # @param [Petra::Components::Section] _section
      #   The section to be persisted
      #
      def persist_section(_section)
        not_implemented
      end

      def lock_transaction

      end

    end
  end
end
