module Petra
  module CoreExt
    module Object
      #
      # @return [Petra::ObjectProxy, Object] A proxy object to be used instead of the
      #   actual object in the transactions' contexts.
      #
      #   Some objects are frozen by default (e.g. +nil+ or the shared instances of TrueClass and FalseClass),
      #   for these, the resulting object proxy is not cached
      #
      def petra
        if frozen?
          Petra::Proxies::ObjectProxy.for(self)
        else
          @__petra_proxy ||= Petra::Proxies::ObjectProxy.for(self)
        end
      end
    end
  end
end