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

      def update_attributes(*args)

      end

      def save(*args)

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
        Petra.log "#{meth} is a getter!", :yellow if __attribute_reader?(meth)
        super
      end

      private

      def __attribute_reader?(method_name)
        return false unless proxied_object.respond_to?(:attributes)

        # Setters are no getters.
        return false if method_name =~ /=$/

        # Check for (boolean) getter methods
        return __attribute_reader?($1) if method_name =~ /(.*)\?$/

        # Check whether the given method name is part
        proxied_object.attributes.keys.include?(method_name.to_s)
      end

      def __attribute_writer?(method_name)
        # Attribute writers have to end with a = (for now)
        return false unless method_name =~ /=$/

        # If the method name ended with a =, we simply have to check if there is
        # a corresponding getter (= an attribute with the given method name)
        __attribute_reader?(method_name[0..-2])
      end

    end
  end
end
