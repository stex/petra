module Petra
  module CoreExt
    module Object
      #
      # @return [Petra::ObjectProxy, Object] A proxy object to be used instead of the
      #   actual object in the transactions' contexts.
      #
      #   Some objects are frozen by default (e.g. +nil+ or the shared instances of TrueClass and FalseClass),
      #   for these, their id is returned.
      #
      def petra
        if frozen?
          self
        else
          @__petra_proxy ||= Petra::ObjectProxy.new(self)
        end
      end
    end
  end
end