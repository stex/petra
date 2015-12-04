module Petra
  module Proxies
    #
    # To avoid messing with the methods defined by ActiveRecord or similar,
    # the programmer should use these proxy objects (object.petra.*) which handle
    # actions on a different level.
    #
    # This class is the base proxy class which can be extended cover
    # certain behaviours that would be too complex to be put inside the configuration.
    #
    class ObjectProxy
      CLASS_NAMES = %w(Object).freeze

      #
      # Determines the available object proxy classes and the ruby classes they
      # can be used for. All classes in the Petra::Proxies namespace are automatically
      # recognized as long as they define a CLASS_NAMES constant.
      #
      # @return [Hash] The available proxy classes in the format ("ClassName" => "ProxyClassName")
      #
      def self.available_proxies
        @proxies ||= (Petra::Proxies.constants).each_with_object({}) do |c, h|
          if (klass = Petra::Proxies.const_get(c)).is_a?(Class) && klass.const_defined?(:CLASS_NAMES)
            klass.const_get(:CLASS_NAMES).each { |n| h[n] = "Petra::Proxies::#{c}" }
          end
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
      def self.for(object)
        # If the given object is configured not to use a possibly existing
        # specialized proxy (e.g. the ActiveRecord::Base proxy), we simply
        # build a default ObjectProxy for it.
        default_proxy = ObjectProxy.new(object)
        return default_proxy unless inherited_config_for(object, :use_specialized_proxy)

        # Otherwise, we search for a specialized proxy for the object's class
        # and its superclasses until we either find one or reach the
        # default ObjectProxy
        klass = object.is_a?(Class) ? object : object.class
        klass = klass.superclass until available_proxies.key?(klass.to_s)
        available_proxies[klass.to_s].constantize.new(object)
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
        Petra.log "Proxying #{meth}(#{args.map(&:inspect).join('nn ')}) to #{@obj.inspect}", :light_gray
        value = @obj.send(meth, *args, &block)

        # Only wrap the result in another petra proxy if it's allowed by the application's configuration
        value.petra.object_config(:proxy_instances, meth.to_s) ? value.petra : value
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

      def initialize(object)
        @obj = object
      end

      #
      # @return [Object] the proxied object
      #
      def proxied_object
        @obj
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
    end
  end
end
