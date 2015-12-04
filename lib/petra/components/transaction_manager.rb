module Petra
  module Components
    module TransactionManager

      def initialize
        @stack = []
      end

      def persistence
        @persistence_adapter ||= Petra.configuration.persistence_adapter.new
      end

    end
  end
end