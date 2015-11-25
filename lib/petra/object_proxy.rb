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
  end
end