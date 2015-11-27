module Petra
  module Configuration
    class ClassConfigurator < Configurator

      DEFAULTS = {
          :wrap_resulting_instances => true
      }.freeze

      def self.for_class(klass)

      end

      def initialize(class_name, options = {})
        @class_name = class_name
        super(options)
      end

      #
      # Sets whether instances of this class should be wrapped in an ObjectProxy
      # if they are the result of a function call to another wrapped object, e.g.
      #   my_class.petra.to_s
      #
      base_config :wrap_resulting_instances

    end
  end
end