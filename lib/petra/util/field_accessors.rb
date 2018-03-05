# frozen_string_literal: true
module Petra
  module Util
    module FieldAccessors
      def self.included(base)
        base.extend(ClassMethods)
      end

      module ClassMethods
        def field_accessor(name)
          define_method(name) do
            self[name]
          end

          define_method("#{name}=") do |value|
            self[name] = value
          end
        end
      end

      def fields
        @fields ||= {}
      end

      def [](key)
        fields[key.to_s]
      end

      def []=(key, value)
        fields[key.to_s] = value
      end
    end
  end
end
