module Petra
  module PersistenceAdapters

    #
    # This class acts as an interface and specifies the methods that
    # a transaction adapter has to implement.
    #
    class Adapter
      self.abstract_class = true

      def start_or_continue
        fail NotImplementedError
      end

      def commit
        fail NotImplementedError
      end

    end

  end
end