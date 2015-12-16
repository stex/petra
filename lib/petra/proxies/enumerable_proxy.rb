module Petra
  module Proxies
    #
    # Module Proxy which is used to proxy classes which include Enumerable, such as
    # Enumerator or Array. It contains wrappers for the default enumerator functions to
    # ensure that objects yielded to their blocks are correctly wrapped in Petra proxies (if needed)
    #
    module EnumerableProxy
      include ModuleProxy
      MODULE_NAMES = %w(Enumerable).freeze

      module InstanceMethods
        def map(*args, &block)
          Petra::Proxies::EnumerableProxy.proxy_entries(proxied_object).map(*args, &block)
        end
      end

      #
      # Ensures the the objects yielded to blocks are actually petra proxies.
      # This is necessary as the internal call to +map+ would be forwarded to the
      # actual Enumerable object and result in unproxied objects.
      #
      # This method will only proxy objects which allow this through the class config
      # as the enum's entries are seen as inherited objects.
      # `[]` is used as method causing the proxy creation as it's closest to what's actually happening.
      #
      def self.proxy_entries(enum, surrogate_method: '[]')
        enum.entries.map { |o| o.petra(inherited: true, configuration_args: [surrogate_method]) }
      end
    end
  end
end
