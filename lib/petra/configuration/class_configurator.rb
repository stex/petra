module Petra
  module Configuration
    class ClassConfigurator < Configurator

      DEFAULTS = {
          :wrap_resulting_instances => true
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

      #
      # Sets whether instances of this class should be wrapped in an ObjectProxy
      # if this is not directly done by the programmer, e.g. as return value
      # from an already proxied object.
      #
      base_config :proxy_instances

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
        new(klass.to_s.camelize)
      end

      #
      # Returns the value for a certain configuration key.
      # If the configuration value is a proc, it will be called
      # with the given +*args+.
      #
      # If the last argument is a hash, it will be used options
      # to customize this methods behaviour instead of being passed
      # to the configuration proc
      #
      # @option options [Boolean] :default_fallback (true)
      #   If set to +true+, the default value for a setting will be returned
      #   if no class setting was set by the application.
      #   If set to +false+, +nil+ is returned if no setting for the
      #   given class exists.
      #
      def __value(name, *args)
        options          = extract_options!(args)
        default_fallback = options.fetch(:default_fallback, true)

        if default_fallback
          v = __configuration.fetch(name.to_sym, DEFAULTS[name.to_sym])
        else
          v = __configuration[name.to_sym]
        end

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
          v.is_a?(Proc) ? v.call(*args) : v
        rescue LocalJumpError => e
          e.exit_value
        end
      end

      #
      # Much like #__value, but it searches for settings
      # with the given name in the current class' ancestors if
      # itself does not have a custom value set.
      #
      # Once it reaches Object, the default value is returned.
      # BasicObject is ignored.
      #
      def __passed_on_value(name, *args)
        original_options = extract_options!(args)
        configurator     = self
        options          = original_options.merge(:default_fallback => false)

        while (klass = configurator.send(:configured_class)) != Object
          v = configurator.__value(name, *(args + [options]))

          # If there is a value for the current class, stop searching and return it
          return v unless v.nil?

          # Build a configurator for the next layer in the class hierarchy
          configurator = Petra.configuration.class_configurator(klass.superclass)
        end

        # If we made it here, our only chance on finding a value
        # is in Object or the default value. It also means that we already
        # have a configurator for Object set up that we can use.
        args << original_options
        configurator.__value(name, *args)
      end

      private


      def configured_class
        @class_name.camelize.constantize
      end

      def __namespaces
        [:models, @class_name]
      end

      def extract_options!(args)
        args.last.is_a?(Hash) ? args.pop : {}
      end

    end
  end
end