module Petra
  module Configuration
    class Base

      #
      # @return [Class] the persistence adapter class used for storing transaction values.
      #   Defaults to use to the cache adapter
      #
      def persistence_adapter_class
        (@persistence_adapter_class ||= 'Petra::PersistenceAdapters::Cache').camelize.constantize
      end

      #
      # Sets the adapter to be used as transaction persistence adapter.
      #
      # Currently, the only options are "Cache" and "ActiveRecord"
      #
      def persistence_adapter=(klass)
        @persistence_adapter_class = "Petra::PersistenceAdapters::#{klass.to_s.camelize}".constantize.to_s
      rescue NameError => e
        fail "The adapter class name 'klass' is not valid (#{e})."
      end


      #
      # Builds a ClassConfigurator to configure petra's behaviour for
      # a certain class in the application
      #
      def configure_class(class_name, &proc)
        configurator = ClassConfigurator.for_class(class_name)
        configurator.instance_eval &proc
        configurator.persist!(__class_configurations)
      end

      #----------------------------------------------------------------
      #                        Helper Methods
      #----------------------------------------------------------------

      def __class_configurations
        @class_configurations ||= {}
      end

      private

      #
      # Adds a new class-wise configuration based on the given configurator
      #
      def add_class_configuration!(class_name, configurator)
        __class_configurations[class_name.to_s] = configurator.options_hash
      end

    end
  end
end