module Petra
  module Configuration
    class Base

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
          __configuration_hash[:persistence_adapter_class] ||= 'Petra::PersistenceAdapters::Cache'
          __configuration_hash[:persistence_adapter_class].camelize.constantize
        end
      rescue NameError => e
        raise "The adapter class name 'klass' is not valid (#{e})."
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

    end
  end
end
