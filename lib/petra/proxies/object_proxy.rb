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
      include Comparable

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

      delegate :to_s, :to => :proxied_object

      #
      # Do not create new proxies for already proxied objects.
      # Instead, return the current proxy object
      #
      def petra(*)
        self
      end

      # Creepy!
      def new(*)
        class_method!
        proxied_object.new.petra
      end

      #
      # Access the proxied object publicly from each petra proxy
      # TODO: This should not leave the proxy!
      #
      # @example
      #   user = User.petra.first
      #   user.unproxied.first_name
      #
      def unproxied
        proxied_object
      end

      #
      # Checks whether the given attribute was altered during the current transaction.
      # Note that an attribute counts as `altered` even if it was reset to its original
      # value in a later transaction step.
      #
      # TODO: Check for dynamic attribute readers?
      #
      def __original_attribute?(attribute_name)
        !transaction.attribute_value?(self, attribute: attribute_name.to_s)
      end

      #
      # Catch all methods which are not defined on this proxy object as they
      # are most likely meant to go to the proxied object
      #
      def method_missing(meth, *args, &block)
        # As calling a superclass method in ruby does not cause method calls within this method
        # to be called within the superclass context, the correct (= the child class') attribute
        # detectors are ran.
        if __attribute_writer?(meth)
          result = handle_attribute_change(meth, *args)
        elsif __attribute_reader?(meth)
          result = handle_attribute_read(meth, *args)
        elsif __dynamic_attribute_reader?(meth)
          result = handle_dynamic_attribute_read(meth, *args)
        else
          result = handle_missing_method(meth, *args, &block)
        end

        Petra.logger.debug "#{object_class_or_self}##{meth}(#{args.map(&:inspect).join(', ')}) => #{result.inspect}"

        result
      # rescue SystemStackError
      #   raise ArgumentError, "Method '#{meth}' lead to a SystemStackError due to `method_missing`"
      end

      #
      # It is necessary to forward #respond_to? queries to
      # the proxied object as otherwise certain calls, especially from
      # the Rails framework itself will fail.
      # Hidden methods are ignored.
      #
      def respond_to_missing?(meth, *)
        proxied_object.respond_to?(meth)
      end

      #
      # Generates an ID for the proxied object based on the class configuration.
      # New objects (= objects which were generated within this transaction) receive
      # an artificial ID
      #
      def __object_id
        if __new?
          @__object_id ||= transaction.objects.next_id
        else
          @__object_id ||= object_config(:id_method, proc_expected: true, base: proxied_object)
        end
      end

      #
      # Generates a unique object key based on the proxied object's class and id
      #
      # @return [String] the generated object key
      #
      def __object_key
        [proxied_object.class, __object_id].map(&:to_s).join('/')
      end

      #
      # Generates a unique attribute key based on the proxied object's class, id and a given attribute
      #
      # @param [String, Symbol] attribute
      #
      # @return [String] the generated attribute key
      #
      def __attribute_key(attribute)
        [proxied_object.class, __object_id, attribute].map(&:to_s).join('/')
      end

      #
      # @return [Boolean] +true+ if the proxied object did not exist before the transaction started
      #
      def __new?
        transaction.objects.new?(self)
      end

      #
      # @return [Boolean] +true+ if the proxied object existed before the transaction started
      #
      def __existing?
        transaction.objects.existing?(self)
      end

      #
      # @return [Boolean] +true+ if the proxied object was created (= initialized + persisted) during
      #   the current transaction
      #
      def __created?
        transaction.objects.created?(self)
      end

      #
      # Very simple spaceship operator based on the object key
      # TODO: See if this causes problems when ID-ordering is expected
      #
      def <=>(other_proxy)
        __object_key <=> other_proxy.__object_key
      end

      protected

      #
      # Sets the given attribute to the given value using the default setter
      # function `name=`. This function is just a convenience method and does not
      # manage the actual write set. Please take a look at #handle_attribute_change instead.
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
      # Calls the given method on the proxied object and optionally
      # wraps the result in another petra proxy
      #
      def handle_missing_method(method_name, *args, &block)
        proxied_object.public_send(method_name, *args, &block)
            .petra(inherited: true, configuration_args: [method_name.to_s])
      end

      #
      # A "dynamic attribute" in this case is a method which usually formats
      # one or multiple attributes and returns the result. An example would be `#{first_name} #{last_name}`
      # within a user class.
      # As methods which are no simple readers/writers are usually forwarded to the proxied
      # object, we have to make sure that these methods are called in this proxy's context, otherwise
      # the used attribute readers would return the actual values, not the ones from our write set.
      #
      # There is no particularly elegant way to achieve this as all forms of bind or instance_eval/exec would
      # not set the correct self (or be incompatible), we generate a new proc from the method's source code
      # and call it within our own context.
      # This should therefore be only used for dynamic attributes like the above example, more complex
      # methods might cause serious problems.
      #
      def handle_dynamic_attribute_read(method_name, *args)
        method_source_proc(method_name).(*args)
      end

      #
      # Logs changes made to attributes of the proxied object.
      # This means that the attribute change is documented within the currently active transaction
      # section and added to the temporary write set.
      #
      def handle_attribute_change(method_name, *args)
        # Remove a possible "=" at the end of the setter method name
        attribute_name = method_name
        attribute_name = method_name[0..-2] if method_name =~ /^.*=$/

        # As there might not be a corresponding getter, our fallback value for
        # the old attribute value is +nil+. TODO: See if this causes unexpected behaviour
        old_value      = nil
        old_value      = proxied_object.send(attribute_name) if __attribute_reader?(attribute_name)

        # As we currently only handle simple setters, we expect the first given argument
        # to be the new attribute value.
        new_value      = args.first #type_cast_attribute_value(attribute_name, args.first)

        transaction.log_attribute_change(self,
                                         attribute: attribute_name,
                                         old_value: old_value,
                                         new_value: new_value,
                                         method:    method_name.to_s)

        new_value
      end

      #
      # Handles a getter method for the proxied object.
      # As attribute changes are not actually forwarded to the actual object,
      # we have to retrieve them from the current (or a past *shiver*) transaction section's
      # write set.
      #
      def handle_attribute_read(method_name, *args)
        if transaction.attribute_value?(self, attribute: method_name)
          # As we read this attribute before, we have the value we read back then on record.
          # Therefore, we may check if the value changed in the mean time which would invalidate
          # the transaction (most likely)
          transaction.verify_attribute_integrity!(self, attribute: method_name)
          transaction.attribute_value(self, attribute: method_name)
        else
          proxied_object.send(method_name, *args).tap do |val|
            transaction.log_attribute_read(self, attribute: method_name, new_value: val, method: method_name)
          end
        end
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

      def initialize(object, inherited = false, object_id: nil)
        @obj         = object
        @inherited   = inherited
        @__object_id = object_id
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
      # @return [Class] the proxied object if it is a class itself, otherwise
      #   the proxied object's class.
      #
      def object_class_or_self
        class_proxy? ? proxied_object : proxied_object.class
      end

      def for_class?(klass)
        proxied_object.is_a?(klass)
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
        object_config(:attribute_reader, method_name.to_s)
      end

      #
      # @see #__attribute_reader?
      #
      def __attribute_writer?(method_name)
        object_config(:attribute_writer, method_name.to_s)
      end

      #
      # @see __#attribute_reader?
      #
      def __dynamic_attribute_reader?(method_name)
        !class_proxy? && object_config(:dynamic_attribute_reader, method_name.to_s)
      end

      #
      # Generates a new Proc object from the source code of a given instance method
      # of the proxied object.
      #
      def method_source_proc(method_name)
        method        = proxied_object.method(method_name.to_sym)
        method_source = method.source.lines[1..-2].join
        # TODO: method.parameters returns the required and optional parameters, these could be handed to the proc
        # TODO: what happens with dynamically generated methods? is there a practical way to achieve this?
        Proc.new do
          eval method_source
        end
      end

      #
      # Performs possible type casts on a value which is about to be set
      # for an attribute. For general ObjectProxy instances, this is simply the identity
      # function, but it might be overridden in more specialized proxies.
      #
      def type_cast_attribute_value(_attribute, value)
        value
      end

      #
      # Raises an exception if proxied object isn't a class.
      # Currently, there is no way to specify which methods are class and instance methods
      # in a specialized proxy, so this at least tells the developer that he did something wrong.
      #
      def class_method!
        unless class_proxy?
          fail Petra::PetraError, 'This method is meant to be used as a singleton method, not an instance method.'
        end
      end

      #
      # @see #class_method!
      #
      def instance_method!
        if class_proxy?
          fail Petra::PetraError, 'This method is meant to be used as an instance method only!'
        end
      end
    end
  end
end
