module Petra
  module Components
    #
    # This class encapsulates the methods a transaction may use to
    # gather information about the objects which were used during its execution.
    #
    class TransactionalObjects
      def initialize(transaction)
        @transaction = transaction
      end

      delegate :sections, :current_section, :to => :@transaction

      #
      # Objects that will have impact during the commit phase
      #
      def fateful

      end

      #
      # Objects that were initialized and persisted during the transaction
      #
      # @param [Class] klass
      #
      # @return [Array<Petra::Proxies::ObjectProxy>]
      #
      def created(klass = nil)
        filtered_objects(:created_objects, klass)
      end

      #
      # Like #created, but it will also include not-yet persisted objects
      # of non-persisted sections
      #
      # @param [Class] klass
      #
      # @return [Array<Petra::Proxies::ObjectProxy>]
      #
      def initialized_or_created(klass = nil)
        filtered_objects(:initialized_or_created_objects, klass)
      end

      #
      # @see #filtered_objects
      #
      # @param [Class] klass
      #
      # @return [Array<Petra::Proxies::ObjectProxy>] objects which were initialized within the transaction,
      #   but not yet object persisted
      #
      def initialized(klass = nil)
        filtered_objects(:initialized_objects, klass)
      end

      #
      # @param [Petra::Proxies::ObjectProxy]
      #
      # @return [Boolean] +true+ if the given object (proxy) was initialized AND persisted during the transaction.
      #
      def created?(proxy)
        created.include?(proxy)
      end

      #
      # @param [Petra::Proxies::ObjectProxy]
      #
      # @return [Boolean] +true+ if the given object (proxy) was initialized, but not yet persisted
      #   during this transaction. This means in particular that the object did not exist before
      #   the transaction started.
      #
      def initialized?(proxy)
        initialized.include?(proxy)
      end

      #
      # @param [Petra::Proxies::ObjectProxy]
      #
      # @return [Boolean] +true+ if the given object did not exist outside of the transaction,
      #   meaning that it was initialized and optionally persisted during its execution
      #
      def new?(proxy)
        current_section.recently_initialized_object?(proxy) || initialized_or_created.include?(proxy)
      end

      #
      # @param [Petra::Proxies::ObjectProxy]
      #
      # @return [Boolean] +true+ if the given object existed before the transaction started
      #
      def existing?(proxy)
        !new?(proxy)
      end

      #----------------------------------------------------------------
      #                          Helpers
      #----------------------------------------------------------------

      def current_numerical_id
        @current_numerical_id ||= (created.max_by(&:__object_id)&.__object_id || 'new_0').match(/new_(\d+)/)[1].to_i
      end

      def inc_current_numerical_id
        @current_numerical_id = current_numerical_id + 1
      end

      def next_id
        format('new_%05d', inc_current_numerical_id)
      end

      private

      #
      # Collects objects of a certain kind from all sections, caches
      # them and filters by a given class name (optionally)
      #
      def filtered_objects(kind, klass = nil)
        @object_cache              ||= {}

        # Instance cache the objects from already persisted sections as they
        # will most likely not change during this section.
        @object_cache[kind.to_sym] ||= sections[0..-2].flat_map(&kind)

        # Add the objects from the current section which may still have changed
        # since we last fetched them
        result                     = @object_cache[kind.to_sym] + current_section.send(kind)

        # If a class (name) was given, only return objects which are of the given type
        klass ? result.select { |p| p.send(:for_class?, klass) } : result
      end

    end
  end
end
