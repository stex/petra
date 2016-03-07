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
      def petra(inherited: false, configuration_args: [])
        # Do not proxy inherited objects if their configuration prohibits it.
        if inherited && !Petra::Proxies::ObjectProxy.inherited_config_for(self, :proxy_instances, *configuration_args)
          return self
        end

        if frozen?
          Petra::Proxies::ObjectProxy.for(self, inherited: inherited)
        else
          @__petra_proxy ||= Petra::Proxies::ObjectProxy.for(self, inherited: inherited)
        end
      end
    end
  end
end
