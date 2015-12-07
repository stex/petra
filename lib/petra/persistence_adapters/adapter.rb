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

    end
  end
end