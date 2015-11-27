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
      @obj.send(meth, *args, &block).petra
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

    #
    # Do not wrap "to_model" in a proxy again as it will confuse certain
    # ActiveSupport helpers
    #
    def to_model
      @obj.to_model
    end

    private

    def proxied_object
      @obj
    end
  end
end