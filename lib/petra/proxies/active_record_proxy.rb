module Petra
  module Proxies
    #
    # A specialized version of the ObjectProxy class to handle ActiveRecord instances.
    # The main difference is, that changes to an object are only persisted if the
    # records were saved, updated or destroyed using the corresponding
    # methods (save, update_attributes, destroy) as we do not have to track e.g.
    # new records (#new actions) or records which could not be saved due to
    # validation errors etc.
    #
    class ActiveRecordProxy < ObjectProxy
      CLASS_NAMES = %w(ActiveRecord::Base).freeze

      delegate :to_model, :to => :proxied_object

      def update_attributes(attributes)
        # TODO: nested parameters...
        attributes.each do |k, v|
          __set_attribute(k, v)
        end
      end

      def save(*)

      end

      # todo: forward to #new and see which attributes are set afterwards
      def create(*args, &block)

      end

      def destroy

      end

      def new_record?

      end

      def persisted?

      end

      def destroyed?

      end

      def method_missing(meth, *args, &block)
        super
      end

      private

      #
      # For ActiveRecord instances, getter and setter methods can usually be derived
      # from the database based attributes.
      # Therefore, this proxy will first check whether the given method name
      # matches one of the instance's attributes before checking for manually defined
      # getter methods.
      # This way, developers don't have to specify each database attribute manually.
      #
      def __attribute_reader?(method_name)
        # If we don't have access to the available attributes, we have to
        # to fall back to normal getter detection.
        return super(method_name) unless proxied_object.respond_to?(:attributes)

        # Setters are no getters. TODO: is super() necessary here?
        return false if method_name =~ /=$/

        # Check for (boolean) getter methods
        return __attribute_reader?($1) if method_name =~ /(.*)\?$/

        # Check whether the given method name is part
        proxied_object.attributes.keys.include?(method_name.to_s) || super(method_name)
      end

      #
      # @see #__attribute_reader?
      #
      def __attribute_writer?(method_name)
        # Attribute writers have to end with a = (for now)
        return false unless method_name =~ /=$/

        # Association setters... not going to be as easy as this
        # return true if !class_proxy? && proxied_object.class.reflect_on_association(method_name[0..-2])

        # If the method name ended with a =, we simply have to check if there is
        # a corresponding getter (= an attribute with the given method name)
        __attribute_reader?(method_name[0..-2]) || super(method_name)
      end

    end
  end
end
