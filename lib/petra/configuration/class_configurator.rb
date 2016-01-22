module Petra
  module Configuration
    class ClassConfigurator < Configurator

      DEFAULTS = {
          :proxy_instances           => false,
          :mixin_module_proxies      => true,
          :use_specialized_proxy     => true,
          :id_method                 => :object_id,
          :lookup_method             => ->(id) { ObjectSpace._id2ref(id) },
          :init_method               => :new,
          :attribute_reader?         => false,
          :attribute_writer?         => ->(name) { /=$/ === name },
          :dynamic_attribute_reader? => false,
          :persistence_method?       => false,
          :destruction_method?       => false
      }.freeze

      #
      # @param [String] class_name
      #   The name of the class to be configured.
      #   .new() should not be called manually, use #for_class instead
      #   which accepts different input types.
      #
      def initialize(class_name)
        @class_name = class_name
        super()
      end

      #----------------------------------------------------------------
      #                      Configuration Keys
      #----------------------------------------------------------------

      #
      # Sets whether instances of this class should be wrapped in an ObjectProxy
      # if this is not directly done by the programmer, e.g. as return value
      # from an already proxied object.
      #
      base_config :proxy_instances

      #
      # Sets whether ObjectProxies should be extended with possibly existing
      # ModuleProxy modules. This is used mainly for +Enumerable+, but you may want
      # to define your own helper modules.
      #
      base_config :mixin_module_proxies

      #
      # Some classes have specialized proxy classes.
      # If this setting is set to +false+, they will not be used in favour of ObjectProxy
      #
      base_config :use_specialized_proxy

      #
      # Sets the method to be used to determine the unique ID of an Object.
      # The ID is needed to identify an object when reloading it within a transaction,
      # so basically a key for our read set.
      #
      # If a block is given, the (:base) object is yielded to it, otherwise,
      # the given method name is assumed to be an instance method in the configured class
      #
      base_config :id_method

      #
      # Sets the method to be used to load an object with a certain unique ID
      # (see +:id_method+).
      #
      # If a block is given, the identifier is yielded to it, otherwise,
      # the given method name is assumed to be a class method accepting
      # a string identifier in the configured class
      #
      base_config :lookup_method

      #
      # Method to initialize a new instance of the proxied class, e.g. `:new` for basic objects
      #
      base_config :init_method

      #
      # Method to destroy an instance of the configured class.
      # This method will be used
      #
      base_config :destroy_method

      #
      # Expects the value (or return value of a block) to be a boolean value
      # depending on whether a method name given as argument is an attribute reader
      #
      base_config :attribute_reader?

      #
      # Expects the value (or return value of a block) to be a boolean value
      # depending on whether a method name given as argument is an attribute reader
      #
      base_config :attribute_writer?

      #
      # Sometimes it might be necessary to use helper methods to combine multiple attributes,
      # e.g. `#name` for `"#{first_name} #{last_name}"`.
      # As calling `#name` would usually be passed to the proxied objects and
      # executed within the object's context instead of the proxy, these methods
      # can be flagged as combined/dynamic attribute readers and will be executed within
      # the proxy's binding.
      # The function is expected to return a boolean value.
      #
      base_config :dynamic_attribute_reader?

      #
      # Expects the value (or return value of a block) to be a boolean value
      # depending on whether a method name given as argument is a method that will persist
      # the current instance.
      # For normal ruby objects this would be every attribute setter (as it would be persisted in
      # the process memory), for e.g. ActiveRecord::Base instances, this is only done by update/save/...
      #
      base_config :persistence_method?

      #----------------------------------------------------------------
      #                        Helper Methods
      #----------------------------------------------------------------

      #
      # Builds a new instance for the given class name.
      # If a configuration for this class already exists, it is loaded and
      # can be retrieved through the corresponding getter methods
      #
      # @param [String, Symbol, Class] klass
      #   The class (name) which will be used to initialize the configurator
      #   and load a possibly already existing configuration
      #
      def self.for_class(klass)
        new(klass.to_s)
      end

      #
      # Returns the value for a certain configuration key.
      # If the configuration value is a proc, it will be called
      # with the given +*args+.
      #
      # If no custom configuration was set for the given +name+, the default
      # value is returned instead.
      #
      # @param [Boolean] proc_expected
      #   If set to +true+, the value is expected to be either a Proc object
      #   or a String/Symbol which is assumed to be a method name.
      #   If the value is something else, an Exception is thrown
      #
      # @param [Object] base
      #   The base object which is used in case +mandatory_proc+ is set to +true+.
      #   If the fetched value is a String or Symbol, it will be used as method
      #   name in a call based on the +base+ object with +*args* as actual parameters, e.g.
      #   base.send(:some_fetched_value, *args)
      #
      def __value(key, *args, proc_expected: false, base: nil)
        v = __configuration.fetch(key.to_sym, DEFAULTS[key.to_sym])

        # As the setting blocks are saved as Proc objects (which are run
        # in their textual scope) and not lambdas (which are run in their caller's scope),
        # Ruby does not allow using the `return` keyword while being inside the
        # block as there is no point to jump back to in their textual scope.
        #
        # When configuring petra using blocks, it is advised to use `next`
        # instead of `return` (which will jump back to the correct position),
        # a workaround is to rescue from possible LocalJumpErrors and simply
        # use their exit value.
        begin
          case v
            when Proc
              v.call(*args)
            when String, Symbol
              return __send_to_base(base, method: v, args: args, key: key) if proc_expected
              v
            else
              __fail_for_key key, 'Value has to be either a Proc or a method name (Symbol/String)' if proc_expected
              v
          end
        rescue LocalJumpError => e
          e.exit_value
        end
      end

      #
      # Tests whether this class configuration has a custom setting for the given key.
      #
      # @return [TrueClass, FalseClass] +true+ if there is a custom setting
      #
      def __value?(name)
        __configuration.key?(name.to_sym)
      end

      #
      # Much like #__value, but it searches for settings
      # with the given name in the current class' ancestors if
      # itself does not have a custom value set.
      #
      def __inherited_value(name, *args)
        configurator = self

        # Search for a custom configuration in the current class and its superclasses
        # until we either reach Object (the lowest level ignoring BasicObject) or
        # found a custom setting.
        until (klass = configurator.send(:configured_class)) == Object || configurator.__value?(name)
          configurator = Petra.configuration.class_configurator(klass.superclass)
        end

        # By now, we have either reached the Object level or found a value.
        # In either case, we are save to retrieve it.
        configurator.__value(name, *args)
      end

      private

      #
      # Raises a Petra::ConfigurationError with information about the key that caused it and a message
      #
      def __fail_for_key(key, message)
        fail Petra::ConfigurationError,
             "The configuration '#{key}' for class '#{@class_name}' seems to be incorrect: #{message}"
      end

      #
      # Tries to .send() the given +method+ to the +base+ object.
      # Exceptions are raised when no base was given or the given base does not respond to the given method.
      #
      def __send_to_base(base, method:, key:, args: [])
        fail ArgumentError, "No base object to send ':#{method}' to was given" unless base

        unless base.respond_to?(method.to_sym)
          if base.is_a?(Class)
            __fail_for_key key, ":#{method} was expected to be a class method in #{base}"
          else
            __fail_for_key key, ":#{method} was expected to be an instance method in #{base.class}"
          end
        end

        base.send(method.to_sym, *args)
      end

      #
      # @return [Class] the class which is configured by this ClassConfigurator
      #
      # Even though ruby class should only contain module separators (::) and camel case words,
      # there might be (framework) class names which do not comply to this.
      # An example would be ActiveRecord's Relation class which seems to be specific
      # for each model class it is used on.
      #
      # Example: User.all #=> <User::ActiveRecord_Relation...>
      #
      # Therefore, we first try to camelize the given class name and if that
      # does not lead us to a valid constant name, we try to pass in the
      # @class_name as is and raise possible errors.
      #
      def configured_class
        @class_name.camelize.safe_constantize || @class_name.constantize
      end

      #
      # @return [Array<Symbol, String>] the namespaces which will be used
      #   when merging this class configuration into the main configuration hash
      #
      def __namespaces
        [:models, @class_name]
      end

      #
      # Removes options from the given arguments if the last element is a Hash
      #
      # @return [Hash] the options extracted from the given arguments or an empty
      #   hash if there were no options given
      #
      def extract_options!(args)
        args.last.is_a?(Hash) ? args.pop : {}
      end
    end
  end
end
