# frozen_string_literal: true

module Petra
  module Components
    #
    # This class encapsulates the methods a transaction may use to
    # gather information about the objects which were used during its execution.
    #
    # It also functions as an object cache, mapping proxy keys to (temporary) object proxies
    #
    class ProxyCache
      def initialize(transaction)
        @transaction = transaction
      end

      #
      # Returns the proxy for the given object key from cache.
      # If there is no valid object cached yet, the given block is executed
      # and its result saved under the given key.
      #
      # @return [Petra::Proxies::ObjectProxy] the object proxy by the given object key
      #
      def fetch(key)
        @cache ||= {}
        return @cache[key.to_s] if @cache.has_key?(key.to_s)
        fail ArgumentError, "Object `#{key}` is not cached and no block was given." unless block_given?
        @cache[key.to_s] = yield
      end

      # Shortcut to retrieve already cached objects.
      # As #[] may not receive a block, it will automatically fail if the
      # cache entry couldn't be found.
      alias_method :[], :fetch

      delegate :sections, :current_section, :verify_attribute_integrity!, to: :@transaction

      #
      # @return [Hash<Petra::Proxies::ObjectProxy, Array<String,Symbol>>]
      #   All attributes which were read during this transaction grouped by the objects (proxies)
      #   they belong to.
      #
      def read_attributes
        sections.each_with_object({}) do |section, h|
          section.read_attributes.each do |proxy, attributes|
            h[proxy] ||= []
            h[proxy] = (h[proxy] + attributes).uniq
          end
        end
      end

      #
      # Objects that will have impact during the commit phase in order of their appearance
      # during the transaction's execution.
      #
      def fateful(klass = nil)
        filtered_objects(:objects, klass)
      end

      #
      # Objects that were read during the transaction
      #
      # @param [Class] klass
      #
      # @return [Array<Petra::Proxies::ObjectProxy>]
      #
      def read(klass = nil)
        filtered_objects(:read_objects, klass)
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
      # @see #filtered_objects
      #
      # @param [Class] klass
      #
      # @return [Array<Petra::Proxies::ObjectProxy>] objects which were destroyed within the transaction
      #
      def destroyed(klass = nil)
        filtered_objects(:destroyed_objects, klass)
      end

      #
      # @param [Petra::Proxies::ObjectProxy] proxy
      #
      # @return [Boolean] +true+ if the given object (proxy) was initialized AND persisted during the transaction.
      #
      def created?(proxy)
        created.include?(proxy)
      end

      #
      # @param [Petra::Proxies::ObjectProxy] proxy
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
      # @param [Petra::Proxies::ObjectProxy] proxy
      #
      # @return [Boolean] +true+ if the given object existed before the transaction started
      #
      def existing?(proxy)
        !new?(proxy)
      end

      #
      # @param [Petra::Proxies::ObjectProxy] proxy
      #
      # @return [Boolean] +true+ if the given object was destroyed during this transaction
      #
      def destroyed?(proxy)
        destroyed.include?(proxy)
      end

      #----------------------------------------------------------------
      #                          Helpers
      #----------------------------------------------------------------

      def current_numerical_id
        # FIXME: The string comparison will not work for numbers > 10! It has to be replaced with a numeric comparison!
        @current_numerical_id ||= (initialized_or_created.max_by(&:__object_id)&.__object_id || 'new_0').match(/new_(\d+)/)[1].to_i
      end

      def inc_current_numerical_id
        @current_numerical_id = current_numerical_id + 1
      end

      def next_id
        format('new_%05d', inc_current_numerical_id)
      end

      #
      # Performs an integrity check on all attributes which were read in this transaction
      #
      # @raise [Petra::ReadIntegrityError] Raised if one of the read attribute has be changed externally
      #
      def verify_read_attributes!(force: false)
        read_attributes.each do |proxy, attributes|
          attributes.each { |a| verify_attribute_integrity!(proxy, attribute: a, force: force) }
        end
      end

      private

      #
      # Collects objects of a certain kind from all sections and filters by a given class name (optionally)
      # There is no caching here as both, sections and log entries will cache the actual objects/sets
      #
      def filtered_objects(kind, klass = nil)
        result = sections.flat_map(&kind)

        # If a class (name) was given, only return objects which are of the given type
        klass ? result.select { |p| p.send(:for_class?, klass) } : result
      end

    end
  end
end
