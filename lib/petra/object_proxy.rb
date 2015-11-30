module Petra
  #
  # To avoid messing with the methods defined by ActiveRecord or similar,
  # the programmer should use these proxy objects (object.petra.*) which handle
  # actions on a different level.
  #
  class ObjectProxy
    def initialize(obj)
      @obj = obj
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
      puts "Proxying #{meth}(#{args.inspect}) to #{@obj.inspect}"
      value = @obj.send(meth, *args, &block)

      # Only wrap the result in another petra proxy if it's allowed by the application's configuration
      value.petra.send(:object_config, :proxy_instances, meth.to_s) ? value.petra : value
    end

    #
    # It is necessary to forward #respond_to? queries to
    # the proxied object as otherwise certain calls, especially from
    # the Rails framework itself will fail.
    #
    def respond_to_missing?(meth, include_all = false)
      @obj.respond_to?(meth)
    end

    #----------------------------------------------------------------
    #                Class specific things (to be moved!)
    #----------------------------------------------------------------

    private

    def proxied_object
      @obj
    end

    def object_config(name, *args)
      # If the proxied object already is a class, we don't use its class (Class)
      # as there is a high chance nobody will ever use this object proxy on
      # this level of meta programming
      klass = proxied_object.is_a?(Class) ? proxied_object : proxied_object.class
      Petra.configuration.class_configurator(klass).__passed_on_value(name, *args)
    end
  end
end