module Petra
  module Configuration
    class Configurator

      #
      # Generates a very basic configuration method which may be called with or
      # without a new value.
      # If it's called without a value, the currently set value is returned.
      # If no value was set yet by the user, the DEFAULT value is used.
      #
      # @param [Object] name
      #   The configuration's name which will become the method name
      #
      def self.base_config(name)
        define_method name do |new_value = nil|
          if new_value.nil?
            value_or_default(name)
          else
            @options[name.to_sym] = new_value
          end
        end
      end

      def initialize(options = {})
        @options = options
      end

      #
      # Persists the new configuration values in the global configuration,
      # meaning that it merges its options into the specific configuration hash
      # under a certain key
      #
      def persist!(configuration_hash)
        configuration_hash.merge!(namespaced_configuration)
      end

      protected

      #
      # @return [Hash] the current configuration options within an
      #   optional namespace chain, mainly to be merged into a global
      #
      def namespaced_configuration

      end

      def value_or_default(name)
        @options.fetch(name.to_sym, DEFAULTS[name.to_sym])
      end

    end
  end
end