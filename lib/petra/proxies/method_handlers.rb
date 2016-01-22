module Petra
  module Proxies
    #
    # This class holds method handlers for certain method groups a proxy
    # may encounter (readers, writers, etc).
    # They are encapsulated in an own class instead of a module mixin to keep the
    # proxy objects as small as possible, hopefully avoiding using the same method names
    # as a proxied object
    #
    class MethodHandlers
      def initialize(proxy, proxy_binding)
        @proxy         = proxy
        @proxy_binding = proxy_binding
      end

      def self.proxy_method(name, underscore_prefix = false)
        define_method(name) do |*args|
          if underscore_prefix
            @proxy.send("__#{name}", *args)
          else
            @proxy.send(name, *args)
          end
        end
      end

      def self.proxy_methods(*methods, underscore_prefix: false)
        methods.each { |m| proxy_method(m, underscore_prefix) }
      end

      proxy_methods :proxied_object, :transaction, :object_config, :class_proxy?
      proxy_methods :attribute_reader?, :type_cast_attribute_value, underscore_prefix: true

      #
      # Yields an array and executes the given handlers afterwards.
      #
      # @return [Object] the first handler's execution result
      #
      # @param [Proc, NilClass] block
      #   As this method itself accepts a block, a proc passed to
      #   method_missing has to be passed in in its normal paramter form
      #
      def execute_missing_queue(method_name, *args, block: nil)
        yield queue = []
        queue << :handle_missing_method if queue.empty?

        send(queue.first, method_name, *args).tap do
          queue[1..-1].each do |handler|
            if block
              send(handler, method_name, *args, &block)
            else
              send(handler, method_name, *args)
            end
          end
        end
      end

      #
      # Calls the given method on the proxied object and optionally
      # wraps the result in another petra proxy
      #
      def handle_missing_method(method_name, *args, &block)
        proxied_object.public_send(method_name, *args, &block)
            .petra(inherited: true, configuration_args: [method_name.to_s])
      end

      #
      # A "dynamic attribute" in this case is a method which usually formats
      # one or multiple attributes and returns the result. An example would be `#{first_name} #{last_name}`
      # within a user class.
      # As methods which are no simple readers/writers are usually forwarded to the proxied
      # object, we have to make sure that these methods are called in this proxy's context, otherwise
      # the used attribute readers would return the actual values, not the ones from our write set.
      #
      # There is no particularly elegant way to achieve this as all forms of bind or instance_eval/exec would
      # not set the correct self (or be incompatible), we generate a new proc from the method's source code
      # and call it within our own context.
      # This should therefore be only used for dynamic attributes like the above example, more complex
      # methods might cause serious problems.
      #
      def handle_dynamic_attribute_read(method_name, *args)
        method_source_proc(method_name).call(*args)
      end

      #
      # Logs changes made to attributes of the proxied object.
      # This means that the attribute change is documented within the currently active transaction
      # section and added to the temporary write set.
      #
      def handle_attribute_change(method_name, *args)
        # Remove a possible "=" at the end of the setter method name
        attribute_name = method_name
        attribute_name = method_name[0..-2] if method_name =~ /^.*=$/

        # As there might not be a corresponding getter, our fallback value for
        # the old attribute value is +nil+. TODO: See if this causes unexpected behaviour
        old_value      = nil
        # To get the actual old value of an attribute reader, we have to
        # act as if it was requested externally by either serving it from the object
        # itself or the transaction's write set.
        # TODO: (Better) way to determine the reader method name, it might be a different one...
        old_value      = handle_attribute_read(attribute_name) if attribute_reader?(attribute_name)

        # As we currently only handle simple setters, we expect the first given argument
        # to be the new attribute value.
        new_value      = args.first #type_cast_attribute_value(attribute_name, args.first)

        transaction.log_attribute_change(@proxy,
                                         attribute: attribute_name,
                                         old_value: old_value,
                                         new_value: new_value,
                                         method:    method_name.to_s)

        new_value
      end

      #
      # Handles a getter method for the proxied object.
      # As attribute changes are not actually forwarded to the actual object,
      # we have to retrieve them from the current (or a past *shiver*) transaction section's
      # write set.
      #
      def handle_attribute_read(method_name, *args)
        if transaction.attribute_value?(@proxy, attribute: method_name)
          # As we read this attribute before, we have the value we read back then on record.
          # Therefore, we may check if the value changed in the mean time which would invalidate
          # the transaction (most likely)
          transaction.verify_attribute_integrity!(@proxy, attribute: method_name)
          transaction.attribute_value(@proxy, attribute: method_name).tap do |result|
            Petra.logger.debug "Served value from write set: #{method_name}  => #{result}", :yellow
          end
        else
          proxied_object.send(method_name, *args).tap do |val|
            transaction.log_attribute_read(@proxy, attribute: method_name, new_value: val, method: method_name)
          end
        end
      end

      #
      # Handles calls to a method which persists the proxied object.
      # As we may not actually call the method on the proxied object, we may only
      # log the persistence.
      #
      # This is a very simple behaviour, so it makes sense to handle persistence methods
      # differently in specialized object proxies (see ActiveRecordProxy)
      #
      # TODO: Log parameters given to the persistence method so they can be used during the commit phase
      #
      def handle_object_persistence(method_name, *)
        transaction.log_object_persistence(@proxy, method: method_name)
        # TODO: Find a better return value for pure persistence calls
        true
      end

      #----------------------------------------------------------------
      #                        Helpers
      #----------------------------------------------------------------

      #
      # Generates a new Proc object from the source code of a given instance method
      # of the proxied object.
      #
      def method_source_proc(method_name)
        method        = proxied_object.method(method_name.to_sym)
        method_source = method.source.lines[1..-2].join
        # TODO: method.parameters returns the required and optional parameters, these could be handed to the proc
        # TODO: what happens with dynamically generated methods? is there a practical way to achieve this?
        Proc.new do
          @proxy_binding.eval method_source
        end
      end

    end
  end
end
