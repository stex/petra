module Petra
  module Configuration
    class Base

      DEFAULTS = {
          :persistence_adapter_class => 'Petra::PersistenceAdapters::Cache',
          :verbose => false
      }.freeze

      #
      # Sets the adapter to be used as transaction persistence adapter.
      #
      # Currently, the only options are "Cache" and "ActiveRecord"
      #
      # @return [Class] the persistence adapter class used for storing transaction values.
      #   Defaults to use to the cache adapter
      #
      def persistence_adapter(klass = nil)
        if klass
          class_name = "Petra::PersistenceAdapters::#{klass.to_s.camelize}".constantize.to_s
          __configuration_hash[:persistence_adapter_class] = class_name
        else
          __config_or_default(:persistence_adapter_class).camelize.constantize
        end
      rescue NameError => e
        raise "The adapter class name 'klass' is not valid (#{e})."
      end

      #
      # Turns petra's verbose mode on or off.
      # If verbose is turned on, more log messages will be generated.
      #
      def verbose(new_value = nil)
        unless new_value.nil?
          __configuration_hash[:verbose] = new_value
        end
        __config_or_default(:verbose)
      end

      #
      # Executes the given block in the context of a ClassConfigurator to
      # configure petra's behaviour for a certain model/class
      #
      def configure_class(class_name, &proc)
        configurator = class_configurator(class_name)
        configurator.instance_eval(&proc)
        configurator.__persist!
      end

      #
      # Builds a ClassConfigurator for the given class or class name.
      #
      # @example Request the configuration for a certain model
      #   Notifications::Notificator.configuration.model_configurator(Subscription).__value(:recipients)
      #
      def class_configurator(class_name)
        ClassConfigurator.for_class(class_name)
      end

      #
      # @return [Hash] the complete configuration or one of its sub-namespaces.
      #   If a namespace does not exists yet, it will be initialized with an empty hash
      #
      # @example Retrieve the {:something => {:completely => {:different => 5}}} namespace
      #   __configuration_hash(:something, :completely)
      #   #=> {:different => 5}
      #
      def __configuration_hash(*sub_keys)
        sub_keys.inject(@configuration ||= {}) do |h, k|
          h[k] ||= {}
        end
      end

      private

      #
      # @return [Object] a base configuration value (non-namespaced) or
      #   the default value (see DEFAULTS) if none was set yet.
      #
      def __config_or_default(name)
        __configuration_hash.fetch(name.to_sym, DEFAULTS[name.to_sym])
      end

    end
  end
end
