module Petra
  module CoreExt
    module Object
      #
      # @return [Petra::ObjectProxy] A proxy object to be used instead of the
      #   actual object in the transactions' contexts
      #
      def petra
        @__petra_proxy ||= Petra::ObjectProxy.new(self)
      end
    end
  end
end