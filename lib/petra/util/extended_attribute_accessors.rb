# frozen_string_literal: true
module Petra
  module Util
    module ExtendedAttributeAccessors
      extend ActiveSupport::Concern

      included do
        extend ClassMethods
      end

      module ClassMethods
        # TODO: Keep track of available accessors on class level
        # TODO: Keep track of the actual values on instance (or class instance) level

        def extended_attr_accessor(name, **options)
          singleton = options.fetch(:singleton, false)
          methods_method, definer_method = :instance_methods, :define_method
          methods_method, definer_method = :singleton_methods, :define_singleton_method if singleton

          unless send(methods_method).include?(:extended_attribute_accessors)
            send(definer_method, :__extended_attribute_accessors__) do |group = :general|
              (@extended_attribute_accessors ||= {})[group.to_sym] ||= {}
            end

            send(definer_method, :extended_attribute_accessors) do |group = :general, only: nil|
              result = __extended_attribute_accessors__(group)
              return result unless only

              result.each_with_object({}) do |(k, v), h|
                h[k] = v.slice(Array(only).map(:to_sym))
              end
            end
          end

          group   = options.fetch(:group, :general)
          default = options[:default]

          send(definer_method, name) do
            accessor = extended_attribute_accessors(group)[name.to_sym] || {}
            accessor[:value] || accessor[:default]
          end

          define_method("#{name}=") do |value|
            self[name] = value
          end
        end
      end




    end
  end
end
