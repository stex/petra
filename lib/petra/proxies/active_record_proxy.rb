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

      #
      # When using ActiveRecord objects, we have a pretty good
      # way of checking whether an object already existing outside the transaction
      # or not by simply checking whether it already has an ID or not.
      #
      def __new?
        !proxied_object.persisted?
      end

      #----------------------------------------------------------------
      #                             CUD
      #----------------------------------------------------------------

      def update_attributes(attributes)
        instance_method!

        # TODO: nested parameters...
        attributes.each do |k, v|
          __set_attribute(k, v)
        end

        transaction.log_object_persistence(self, method: 'update_attributes')
      end

      def save(*)
        instance_method!
      end

      # Still Creepy!
      def new(attributes = {})
        super.tap do |o|
          transaction.log_object_initialization(o, method: 'new')

          # TODO: nested parameters...
          attributes.each do |k, v|
            o.__set_attribute(k, v)
          end
        end
      end

      def create(attributes = {})
        class_method!
        new(attributes).tap do |o|
          # Set the called method to #save as we will use #new -> #save in the commit phase
          transaction.log_object_persistence(o, method: 'save')
        end
      end

      def destroy
        instance_method!
      end

      #----------------------------------------------------------------
      #                        Finding Records
      #----------------------------------------------------------------

      #
      # Ugly wrapper around AR's #find method which allows
      # searching for records which were created during a transaction.
      #
      def find(*ids)
        class_method!

        # Extract non-AR IDs. Currently, the only way to detect them is to
        # search for the pattern "new_DIGITS" which may conflict with custom primary keys,
        # e.g. the `friendly_id` gem
        new_ids = ids.select { |id| id =~ /^new_\d+$/ }

        # Try to look up objects which were created during this transaction and match
        # the given IDs. This will automatically raise ActiveRecord::RecordNotFound errors
        # if an object isn't found.
        new_records = new_records_from_ids(new_ids)

        # Fetch the records which already existed outside the transaction and
        # add the temporary objects to the result
        result = handle_missing_method('find', ids - new_ids) + new_records

        # To emulate AR's behaviour, return the first result if we only got one.
        result.size == 1 ? result.first : result
      end

      #----------------------------------------------------------------
      #                        Persistence Flags
      #----------------------------------------------------------------

      #
      # @return [Boolean] +true+ if the proxied object was initialized during the transaction
      #   and hasn't been object persisted yet
      #
      def new_record?
        instance_method!
        !__existing? && !__created?
      end

      def persisted?
        instance_method!
        __existing? || __created?
      end

      def destroyed?
        instance_method!
      end

      #----------------------------------------------------------------
      #                     Rails' Internal Helpers
      #----------------------------------------------------------------

      #
      # Instead of forwarding #to_model to the proxied object, we have to
      # return the proxy to ensure that Rails' internal methods (e.g. url_for)
      # get the correct data
      #
      def to_model(*)
        self
      end

      #
      # If the record existed before the transaction started, we may simply return its ID.
      # Otherwise... well, we return our internal ID which isn't the best solution, but it at
      # least allows us to work with __new? records mostly like we would with __existing?
      #
      def to_param
        __existing? ? proxied_object.to_param : __object_id
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

      #
      # @return [Array<Petra::Proxies::ObjectProxy>] records which were created during this transaction.
      #   The cannot be found using AR's finder methods as they are not yet persisted in the database.
      #
      def new_records_from_ids(ids)
        ids.map do |new_id|
          unless (object = transaction.objects.created(proxied_object).find { |o| o.__object_id == new_id })
            fail ::ActiveRecord::RecordNotFound, "Couldn't find #{name} with '#{primary_key}'=#{new_id}"
          end
          object
        end
      end
    end
  end
end
