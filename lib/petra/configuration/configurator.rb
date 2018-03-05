# frozen_string_literal: true
module Petra
  module Configuration
    class Configurator

      #
      # Generates a very basic configuration method which accepts a
      # block or input value (see +options+)
      #
      # @param [Object] name
      #   The configuration's name which will become the method name
      #
      # @param [Boolean] accept_value
      #   If set to +true+, the resulting method accepts not only a block,
      #   but also a direct value.
      #   If both, a value and a block are given, the block takes precedence
      #
      def self.base_config(name, accept_value: true)
        if accept_value
          define_method name do |value = nil, &proc|
            if proc
              __configuration[name.to_sym] = proc
            elsif !value.nil?
              __configuration[name.to_sym] = value
            else
              fail ArgumentError, 'Either a value or a configuration block have to be given.'
            end
          end
        else
          define_method name do |&proc|
            fail(ArgumentError, 'A configuration block has to be given.') unless proc
            __configuration[name.to_sym] = proc
          end
        end
      end

      def initialize
        @options = Petra.configuration.__configuration_hash(*__namespaces).deep_dup
      end

      #
      # Persists the new configuration values in the global configuration,
      # meaning that it merges its options into the specific configuration hash
      # under a certain key
      #
      def __persist!
        Petra.configuration.__configuration_hash(*__namespaces).deep_merge!(__configuration)
      end

      protected

      #
      # @return [Array<Symbol>] the current configuration options within an
      #   optional namespace chain, mainly to be merged into a global
      #
      def __namespaces
        not_implemented
      end

      def __configuration
        @options
      end

    end
  end
end
