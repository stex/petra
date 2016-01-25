module Petra
  module Configuration
    class Base

      DEFAULTS = {
          :persistence_adapter_name    => 'file',
          :log_level                   => 'debug',
          :storage_directory           => '/tmp',
          :instant_read_integrity_fail => true
      }.freeze

      #----------------------------------------------------------------
      #                       Configuration Keys
      #----------------------------------------------------------------

      #
      # Configures whether a read integrity error will be automatically
      # detected whenever an attribute is read.
      # If this is set to +false+, the read values will only be checked during
      # the commit phase.
      #
      def instant_read_integrity_fail(new_value = nil)
        if !new_value.nil?
          __configuration_hash[:instant_read_integrity_fail] = new_value
        else
          __config_or_default(:instant_read_integrity_fail)
        end
      end

      #
      # Sets the adapter to be used as transaction persistence adapter.
      # An adapter has to be registered before it may be used (see Adapter)
      #
      # @return [Class] the persistence adapter class used for storing transaction values.
      #   Defaults to use to the cache adapter
      #
      def persistence_adapter(name = nil)
        if name
          unless Petra::PersistenceAdapters::Adapter.registered_adapter?(name)
            fail Petra::ConfigurationError,
                 "The given adapter `#{name}` hasn't been registered. " \
                 "Valid adapters are: #{Petra::PersistenceAdapters::Adapter.registered_adapters.keys.inspect}"
          end
          __configuration_hash[:persistence_adapter_name] = name
        else
          Petra::PersistenceAdapters::Adapter[__config_or_default(:persistence_adapter_name)].constantize
        end
      end

      #
      # Sets/gets the directory petra may store its various files in.
      # This currently includes lock files and the file persistence adapter
      # TODO: Move this to adapter configurations?
      #
      def storage_directory(new_value = nil)
        if new_value
          __configuration_hash[:lock_file_dir] = new_value
        else
          Pathname.new(__config_or_default(:lock_file_dir))
        end
      end

      #
      # The log level for petra. Only messages which are greater or equal to this level
      # will be shown in the output
      #
      def log_level(new_value = nil)
        if new_value
          __configuration_hash[:log_level] = new_value.to_s
        else
          __config_or_default(:log_level).to_sym
        end
      end

      #----------------------------------------------------------------
      #                         Helper Methods
      #----------------------------------------------------------------

      #
      # A shortcut method to set +proxy_instances+ for multiple classes at once
      # without having to +configure_class+ for each one.
      #
      # @example
      #     proxy_class_instances 'Array', 'Enumerator', Hash
      #
      def proxy_class_instances(*class_names)
        class_names.each do |klass|
          configure_class(klass) do
            proxy_instances true
          end
        end
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

      alias_method :[], :class_configurator

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
