# frozen_string_literal: true

module Petra
  module Util
    #
    # Helper module to add register functionality to a class
    # This means that other classes may register themselves under a certain name
    #
    module Registrable
      def self.included(base)
        base.extend ClassMethods
      end

      module ClassMethods
        #
        # Generates helper methods from the given name.
        #
        # @example Type register
        #   acts_as_register(:type)
        #   => registered_types
        #   => register_type(type)
        #   => registered_type(type) #=> value
        #   => registered_type?(type) #=> true/false
        #
        def acts_as_register(name)
          name = name.to_s

          define_singleton_method("registered_#{name.pluralize}") do
            @registered_components ||= {}
            @registered_components[name.to_s] ||= {}
          end

          define_singleton_method("registered_#{name}") do |key|
            send("registered_#{name.pluralize}")[key.to_s]
          end

          define_singleton_method("register_#{name}") do |key, value|
            send("registered_#{name.pluralize}")[key.to_s] = value
          end

          define_singleton_method("registered_#{name}?") do |key|
            send("registered_#{name.pluralize}").has_key?(key.to_s)
          end
        end
      end
    end
  end
end
