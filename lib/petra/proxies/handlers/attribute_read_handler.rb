# frozen_string_literal: true

module Petra
  module Proxies
    module Handlers
      class AttributeReadHandler < MissingMethodHandler
        add_constraint(:before, :object_persistence)

        def self.identifier
          :attribute_read
        end

        def applicable?(method_name)
          proxy.send(:__attribute_reader?, method_name)
        end

        def handle(method_name, *args)
          if transaction.attribute_value?(@proxy, attribute: method_name)
            # As we read this attribute before, we have the value we read back then on record.
            # Therefore, we may check if the value changed in the mean time which would invalidate
            # the transaction (most likely).
            transaction.verify_attribute_integrity!(@proxy, attribute: method_name)

            transaction.attribute_value(@proxy, attribute: method_name).tap do |result|
              Petra.logger.debug "Served value from write set: #{method_name}  => #{result}", :yellow, :bold
            end
          elsif transaction.read_attribute_value?(@proxy, attribute: method_name)
            # If we didn't write the attribute before, we may at least have already read it.
            # In this case, we don't have to generate a new read log entry
            transaction.verify_attribute_integrity!(@proxy, attribute: method_name)

            # We also may simply return the last accepted read set value
            transaction.read_attribute_value(@proxy, attribute: method_name).tap do |result|
              Petra.logger.debug "Re-read attribute: #{method_name}  => #{result}", :yellow, :bold
            end
          else
            proxied_object.send(method_name, *args).tap do |val|
              transaction.log_attribute_read(@proxy, attribute: method_name, value: val, method: method_name)
            end
          end
        end
      end
    end
  end
end
