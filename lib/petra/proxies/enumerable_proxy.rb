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
      INCLUDES     = [Enumerable]

      module InstanceMethods
        #
        # We have to define our own #each method for the singleton class' Enumerable
        # It basically just wraps the original enum's entries in proxies and executes
        # the "normal" #enum
        #
        def each(&block)
          Petra::Proxies::EnumerableProxy.proxy_entries(proxied_object).each(&block)
        end
      end

      #
      # Ensures the the objects yielded to blocks are actually petra proxies.
      # This is necessary as the internal call to +each+ would be forwarded to the
      # actual Enumerable object and result in unproxied objects.
      #
      # This method will only proxy objects which allow this through the class config
      # as the enum's entries are seen as inherited objects.
      # `[]` is used as method causing the proxy creation as it's closest to what's actually happening.
      #
      # @return [Array<Petra::Proxies::ObjectProxy>]
      #
      def self.proxy_entries(enum, surrogate_method: '[]')
        enum.entries.map { |o| o.petra(inherited: true, configuration_args: [surrogate_method]) }
      end
    end
  end
end
