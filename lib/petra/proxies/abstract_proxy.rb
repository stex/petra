# frozen_string_literal: true

module Petra
  module Proxies
    class AbstractProxy

      protected

      #
      # Determines the available object proxy classes and the ruby classes they
      # can be used for. All classes in the Petra::Proxies namespace are automatically
      # recognized as long as they define a CLASS_NAMES constant.
      #
      # If multiple proxies specify the same class name, the last one by sorting wins.
      #
      # @return [Hash] The available proxy classes in the format ("ClassName" => "ProxyClassName")
      #
      def self.available_class_proxies
        @class_proxies ||= Petra::Proxies.constants.each_with_object({}) do |c, h|
          klass = Petra::Proxies.const_get(c)
          # Skip non-class constants (this includes modules)
          next unless klass.is_a?(Class)
          # Skip every class which is not an ObjectProxy. There shouldn't be any
          # in this namespace, but you never know...
          next unless klass <= Petra::Proxies::ObjectProxy
          # Skip proxy classes which do not specify which classes
          # they were built for
          next unless klass.const_defined?(:CLASS_NAMES)

          klass.const_get(:CLASS_NAMES).each { |n| h[n] = "Petra::Proxies::#{c}" }
        end
      end

      #
      # @see #available_class_proxies
      #
      # Returns only module proxies
      #
      def self.available_module_proxies
        @module_proxies ||= Petra::Proxies.constants.each_with_object({}) do |c, h|
          klass = Petra::Proxies.const_get(c)
          next unless klass.is_a?(Module)
          next unless klass.included_modules.include?(Petra::Proxies::ModuleProxy)
          next unless klass.const_defined?(:MODULE_NAMES)

          klass.const_get(:MODULE_NAMES).each { |n| h[n] = "Petra::Proxies::#{c}" }
        end
      end

      #
      # Builds an ObjectProxy for the given object.
      # If a more specific proxy class exists for the given object,
      # it will be used instead of the generic Petra::Proxies::ObjectProxy.
      #
      # If there is no proxy for the exact class of the given +object+,
      # its superclasses are automatically tested.
      #
      def self.for(object, inherited: false, **options)
        # If the given object is configured not to use a possibly existing
        # specialized proxy (e.g. the ActiveRecord::Base proxy), we simply
        # build a default ObjectProxy for it, but we'll still try to extend it using
        # available ModuleProxies
        default_proxy = ObjectProxy.new(object, inherited, **options)
        default_proxy.send :mixin_module_proxies!
        return default_proxy unless inherited_config_for(object, :use_specialized_proxy)

        # Otherwise, we search for a specialized proxy for the object's class
        # and its superclasses until we either find one or reach the
        # default ObjectProxy
        klass = object.is_a?(Class) ? object : object.class
        klass = klass.superclass until available_class_proxies.key?(klass.to_s)
        proxy = available_class_proxies[klass.to_s].constantize.new(object, inherited, **options)

        # If we reached Object, we might still find one or more ModuleProxy module we might
        # mix into the resulting ObjectProxy. Otherwise, the specialized proxy will most likely
        # have included the necessary ModuleProxies itself.
        proxy.send(:mixin_module_proxies!) if proxy.instance_of?(Petra::Proxies::ObjectProxy)
        proxy
      end

      #
      # As it might happen that a custom proxy has to be defined for behaviour
      # introduced to different classes as an included module (an example would be Enumerable),
      # it has to be possible to define an equivalent to object proxies for them.
      # This function inspects all modules which were previously included into
      # the proxied object's singleton class and automatically adds matching module proxies.
      #
      # Please take a look at Petra::Proxies::EnumerableProxy for an example module proxy
      #
      def mixin_module_proxies!
        # Neither symbols nor fixnums may have singleton classes, see the corresponding Kernel method
        return if proxied_object.is_a?(Integer) || proxied_object.is_a?(Symbol)

        # Do not load ModuleProxies if the object's configuration denies it
        return unless object_config(:mixin_module_proxies)

        proxied_object.singleton_class.included_modules.each do |mod|
          proxy_module = Petra::Proxies::ObjectProxy.available_module_proxies[mod.to_s].try(:constantize)
          # Skip all included modules without ModuleProxies
          next unless proxy_module

          singleton_class.class_eval do
            # Extend the proxy with the module proxy's class methods
            extend proxy_module.const_get(:ClassMethods) if proxy_module.const_defined?(:ClassMethods)

            # Include the module proxy's instance methods
            include proxy_module.const_get(:InstanceMethods) if proxy_module.const_defined?(:InstanceMethods)

            if proxy_module.const_defined?(:INCLUDES)
              proxy_module.const_get(:INCLUDES).each { |m| include m }
            end
          end
        end
      end

      #
      # @return [Petra::Components::Transaction] the currently active transaction
      #
      def transaction
        Petra.transaction_manager.current_transaction
      end

      #
      # Retrieves a configuration value with the given name respecting
      # custom configurations made for its class (or class family)
      #
      def self.inherited_config_for(object, name, *args)
        # If the proxied object already is a class, we don't use its class (Class)
        # as there is a high chance nobody will ever use this object proxy on
        # this level of meta programming
        klass = object.is_a?(Class) ? object : object.class
        Petra.configuration.class_configurator(klass).__inherited_value(name, *args)
      end

      #
      # @see #inherited_config_for, the proxied object is automatically passed in
      #    as first parameter
      #
      def object_config(name, *args)
        self.class.inherited_config_for(proxied_object, name, *args)
      end

      delegate :inspect, to: :proxied_object

      private

      def initialize
      end

    end
  end
end
