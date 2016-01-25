module Petra
  module Proxies
    #
    # To avoid messing with the methods defined by ActiveRecord or similar,
    # the programmer should use these proxy objects (object.petra.*) which handle
    # actions on a different level.
    #
    # This class is the base proxy class which can be extended to cover
    # certain behaviours that would be too complex to be put inside the configuration.
    #
    class ObjectProxy < AbstractProxy
      include Comparable

      CLASS_NAMES = %w(Object).freeze

      delegate :to_s, :to => :proxied_object

      #
      # Do not create new proxies for already proxied objects.
      # Instead, return the current proxy object
      #
      def petra(*)
        self
      end

      # Creepy!
      def new(*)
        class_method!
        proxied_object.new.petra
      end

      #
      # Access the proxied object publicly from each petra proxy
      # TODO: This should not leave the proxy!
      #
      # @example
      #   user = User.petra.first
      #   user.unproxied.first_name
      #
      def unproxied
        proxied_object
      end

      #
      # Checks whether the given attribute was altered during the current transaction.
      # Note that an attribute counts as `altered` even if it was reset to its original
      # value in a later transaction step.
      #
      # TODO: Check for dynamic attribute readers?
      #
      def __original_attribute?(attribute_name)
        !transaction.attribute_value?(self, attribute: attribute_name.to_s)
      end

      #
      # Catch all methods which are not defined on this proxy object as they
      # are most likely meant to go to the proxied object
      #
      # Also checks a few special cases like attribute reads/changes.
      # Please note that a method may be e.g. a persistence method AND an attribute writer
      # (for normal objects, every attribute write would be persisted to memory), so
      # we have to execute all matching handlers in a queue.
      #
      def method_missing(meth, *args, &block)
        # As calling a superclass method in ruby does not cause method calls within this method
        # to be called within the superclass context, the correct (= the child class') attribute
        # detectors are run.
        result = __handlers.execute_missing_queue(meth, *args, block: block) do |queue|
          queue << :handle_attribute_change if __attribute_writer?(meth)
          queue << :handle_attribute_read if __attribute_reader?(meth)
          queue << :handle_dynamic_attribute_read if __dynamic_attribute_reader?(meth)
          queue << :handle_object_persistence if __persistence_method?(meth)
        end

        Petra.logger.debug "#{object_class_or_self}##{meth}(#{args.map(&:inspect).join(', ')}) => #{result.inspect}"

        result
      rescue SystemStackError => e
        exception = ArgumentError.new("Method '#{meth}' lead to a SystemStackError due to `method_missing`")
        exception.set_backtrace(e.backtrace.uniq)
        raise exception
      end

      #
      # It is necessary to forward #respond_to? queries to
      # the proxied object as otherwise certain calls, especially from
      # the Rails framework itself will fail.
      # Hidden methods are ignored.
      #
      def respond_to_missing?(meth, *)
        proxied_object.respond_to?(meth)
      end

      #
      # Generates an ID for the proxied object based on the class configuration.
      # New objects (= objects which were generated within this transaction) receive
      # an artificial ID
      #
      def __object_id
        if __new?
          @__object_id ||= transaction.objects.next_id
        else
          @__object_id ||= object_config(:id_method, proc_expected: true, base: proxied_object)
        end
      end

      #
      # Generates a unique object key based on the proxied object's class and id
      #
      # @return [String] the generated object key
      #
      def __object_key
        [proxied_object.class, __object_id].map(&:to_s).join('/')
      end

      #
      # Generates a unique attribute key based on the proxied object's class, id and a given attribute
      #
      # @param [String, Symbol] attribute
      #
      # @return [String] the generated attribute key
      #
      def __attribute_key(attribute)
        [proxied_object.class, __object_id, attribute].map(&:to_s).join('/')
      end

      #
      # @return [Boolean] +true+ if the proxied object did not exist before the transaction started
      #
      def __new?
        transaction.objects.new?(self)
      end

      #
      # @return [Boolean] +true+ if the proxied object existed before the transaction started
      #
      def __existing?
        transaction.objects.existing?(self)
      end

      #
      # @return [Boolean] +true+ if the proxied object was created (= initialized + persisted) during
      #   the current transaction
      #
      def __created?
        transaction.objects.created?(self)
      end

      #
      # @return [Boolean] +true+ if the proxied object was destroyed during the transaction
      #
      def __destroyed?
        transaction.objects.destroyed?(self)
      end

      #
      # Very simple spaceship operator based on the object key
      # TODO: See if this causes problems when ID-ordering is expected.
      #   For existing objects that shouldn't be the case in most situations as
      #   a collection mostly contains only objects of one kind
      #
      def <=>(other_proxy)
        __object_key <=> other_proxy.__object_key
      end

      protected

      #----------------------------------------------------------------
      #                        Commit Phase
      #----------------------------------------------------------------

      #
      # Applies the action performed in the given log entry to the proxied object (if applicable)
      #
      # @param [Petra::Components::LogEntry] log_entry
      #
      def __apply__(log_entry)
        # We do not have to apply attribute reads at all as they do not (should not!)
        # change the object
        return true if log_entry.attribute_read?
        # If we already have this proxy, the object has been initialized by the log entry
        return true if log_entry.object_initialization?

        case log_entry.kind.to_s
          when 'attribute_change'
            proxied_object.send(log_entry.method, log_entry.new_value)
          when 'object_persistence'
            # TODO: React to `false` responses from persistence methods?
            # This would however cause problems with normal objects (setter <=> persistence method) and boolean values
            proxied_object.send(log_entry.method)
          when 'object_destruction'
            # TODO: React to `false` responses from destruction methods?
            proxied_object.send(log_entry.method)
          else
            Petra.logger.warn "Unexpected log entry type `#{log_entry.kind}`", :red
        end
      end

      #
      # Tries to `unapply` the given log entry.
      # Currently, the only log entries which can be processed here are attribute changes
      # as we don't know how to undo persistence or destruction actions
      #
      # @param [Petra::Components::LogEntry] log_entry
      #
      def __undo_application__(log_entry)

      end

      #----------------------------------------------------------------
      #                    Method Group Detectors
      #----------------------------------------------------------------

      #
      # Checks whether the given method name is part of the configured attribute reader
      # methods within the currently proxied class
      #
      def __attribute_reader?(method_name)
        object_config(:attribute_reader?, method_name.to_s)
      end

      #
      # @see #attribute_reader?
      #
      def __attribute_writer?(method_name)
        object_config(:attribute_writer?, method_name.to_s)
      end

      #
      # @see #attribute_reader?
      #
      # Currently, classes may not use dynamic attribute readers
      #
      def __dynamic_attribute_reader?(method_name)
        !class_proxy? && object_config(:dynamic_attribute_reader?, method_name.to_s)
      end

      #
      # @return [Boolean] +true+ if the given method would persist the
      #   proxied object
      #
      def __persistence_method?(method_name)
        !class_proxy? && object_config(:persistence_method?, method_name.to_s)
      end

      #
      # @return [Boolean] +true+ if the given method name is a "destructor" of the
      #   proxied object
      #
      def __destruction_method?(method_name)
        !class_proxy? && object_config(:destruction_method?, method_name.to_s)
      end

      #
      # Sets the given attribute to the given value using the default setter
      # function `name=`. This function is just a convenience method and does not
      # manage the actual write set. Please take a look at #handle_attribute_change instead.
      #
      # @param [String, Symbol] attribute
      #   The attribute name. The proxied object is expected to have a corresponding public setter method
      #
      # @param [Object] new_value
      #
      def __set_attribute(attribute, new_value)
        public_send("#{attribute}=", new_value)
      end

      def __handlers
        @__handlers ||= Petra::Proxies::MethodHandlers.new(self, binding)
      end

      def initialize(object, inherited = false, object_id: nil)
        @obj         = object
        @inherited   = inherited
        @__object_id = object_id
      end

      #
      # @return [Object] the proxied object
      #
      def proxied_object
        @obj
      end

      #
      # @return [Boolean] +true+ if the proxied object is a class
      #
      def class_proxy?
        proxied_object.is_a?(Class)
      end

      #
      # @return [Class] the proxied object if it is a class itself, otherwise
      #   the proxied object's class.
      #
      def object_class_or_self
        class_proxy? ? proxied_object : proxied_object.class
      end

      #
      # @return [Boolean] +true+ if the proxied object is a +klass+
      #
      def for_class?(klass)
        proxied_object.is_a?(klass)
      end

      #
      # Performs possible type casts on a value which is about to be set
      # for an attribute. For general ObjectProxy instances, this is simply the identity
      # function, but it might be overridden in more specialized proxies.
      #
      def __type_cast_attribute_value(_attribute, value)
        value
      end

      #
      # Raises an exception if proxied object isn't a class.
      # Currently, there is no way to specify which methods are class and instance methods
      # in a specialized proxy, so this at least tells the developer that he did something wrong.
      #
      def class_method!
        unless class_proxy?
          fail Petra::PetraError, 'This method is meant to be used as a singleton method, not an instance method.'
        end
      end

      #
      # @see #class_method!
      #
      def instance_method!
        if class_proxy?
          fail Petra::PetraError, 'This method is meant to be used as an instance method only!'
        end
      end


    end
  end
end
