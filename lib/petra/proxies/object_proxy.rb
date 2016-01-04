module Petra
  module Proxies
    #
    # To avoid messing with the methods defined by ActiveRecord or similar,
    # the programmer should use these proxy objects (object.petra.*) which handle
    # actions on a different level.
    #
    # This class is the base proxy class which can be extended to cover
    # certain behaviours that would be too complex to be put inside the configuration.
    #
    class ObjectProxy
      CLASS_NAMES = %w(Object).freeze

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
        @class_proxies ||= (Petra::Proxies.constants).each_with_object({}) do |c, h|
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
        @module_proxies ||= (Petra::Proxies.constants).each_with_object({}) do |c, h|
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
      def self.for(object, inherited: false)
        # If the given object is configured not to use a possibly existing
        # specialized proxy (e.g. the ActiveRecord::Base proxy), we simply
        # build a default ObjectProxy for it, but we'll still try to extend it using
        # available ModuleProxies
        default_proxy = ObjectProxy.new(object, inherited)
        default_proxy.send :mixin_module_proxies!
        return default_proxy unless inherited_config_for(object, :use_specialized_proxy)

        # Otherwise, we search for a specialized proxy for the object's class
        # and its superclasses until we either find one or reach the
        # default ObjectProxy
        klass = object.is_a?(Class) ? object : object.class
        klass = klass.superclass until available_class_proxies.key?(klass.to_s)
        proxy = available_class_proxies[klass.to_s].constantize.new(object, inherited)

        # If we reached Object, we might still find one or more ModuleProxy module we might
        # mix into the resulting ObjectProxy. Otherwise, the specialized proxy will most likely
        # have included the necessary ModuleProxies itself.
        proxy.send(:mixin_module_proxies!) if proxy.instance_of?(Petra::Proxies::ObjectProxy)
        proxy
      end

      delegate :to_s, :to => :proxied_object

      #
      # Do not create new proxies for already proxied objects.
      # Instead, return the current proxy object
      #
      def petra
        self
      end

      #
      # Catch all methods which are not defined on this proxy object as they
      # are most likely meant to go to the proxied object
      #
      def method_missing(meth, *args, &block)
        handle_attribute_changes(meth, *args)

        # Only wrap the result in another petra proxy if it's allowed by the application's configuration
        proxied_object.public_send(meth, *args, &block).petra(inherited: true, configuration_args: [meth.to_s]).tap do |o|
          if o.is_a?(Petra::Proxies::ObjectProxy)
            Petra.log "Proxying #{meth}(#{args.map(&:inspect).join(', ')}) to #{@obj.inspect} #=> #{o.class}"
          end
        end
      end

      #
      # It is necessary to forward #respond_to? queries to
      # the proxied object as otherwise certain calls, especially from
      # the Rails framework itself will fail.
      # Hidden methods are ignored.
      #
      def respond_to_missing?(meth, _ = false)
        @obj.respond_to?(meth)
      end

      protected

      #
      # Sets the given attribute to the given value
      #
      # @param [String, Symbol] attribute
      #   The attribute name. The proxied object is expected to have a corresponding public setter method
      #
      # @param [Object] new_value
      #
      def __set_attribute(attribute, new_value)
        public_send("#{attribute}=", new_value)
      end

      #
      # Logs changes made to attributes of the proxied object
      #
      def handle_attribute_changes(method_name, *args)
        # If the given method is none of the classes attribute writers, we do not have to
        # handle an attribute change.
        # As calling a superclass method in ruby does not cause method calls within this method
        # to be called within the superclass context, the correct (= the child class') attribute
        # detectors are ran.
        return unless __attribute_writer?(method_name)

        # Remove a possible "=" at the end of the setter method name
        attribute_name = method_name
        attribute_name = method_name[0..-2] if method_name =~ /^.*=$/

        # As there might not be a corresponding getter, our fallback value for
        # the old attribute value is +nil+. TODO: See if this causes unexpected behaviour
        old_value      = nil
        old_value      = proxied_object.send(attribute_name) if __attribute_reader?(attribute_name)

        # As we currently only handle simple setters, we expect the first given argument
        # to be the new attribute value.
        new_value      = args.first

        transaction.log_attribute_change(self, attribute: attribute_name, old_value: old_value, new_value: new_value)
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
        return if proxied_object.is_a?(Fixnum) || proxied_object.is_a?(Symbol)

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
          end
        end
      end

      def initialize(object, inherited = false)
        @obj       = object
        @inherited = inherited
      end

      #
      # @return [Object] the proxied object
      #
      def proxied_object
        @obj
      end

      #
      # @return [Boolean] +true+ if the proxied object is a class
      #
      def class_proxy?
        proxied_object.is_a?(Class)
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

      #
      # Checks whether the given method name is part of the configured attribute reader
      # methods within the currently proxied class
      #
      def __attribute_reader?(method_name)
        object_config(:attr_readers).map(&:to_s).include?(method_name.to_s)
      end

      #
      # @see #__attribute_reader?
      #
      def __attribute_writer?(method_name)
        object_config(:attr_writers).map(&:to_s).include?(method_name.to_s)
      end
    end
  end
end
