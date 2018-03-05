# frozen_string_literal: true

require 'petra/components/log_entry'

module Petra
  module Components
    #
    # An EntrySet is a collection of log entries for a certain section.
    # It may be used to chain-filter entries, e.g. only object_persisted entries for a certain proxy.
    #
    # TODO: Probably be Enumerator::Lazy...
    #
    class EntrySet < Array

      #----------------------------------------------------------------
      #                          Filters
      #----------------------------------------------------------------

      def for_proxy(proxy)
        wrap { select { |e| e.for_object?(proxy.__object_key) } }
      end

      def of_kind(kind)
        wrap { select { |e| e.kind?(kind) } }
      end

      def for_attribute_key(key)
        wrap { select { |e| e.attribute_key.to_s == key.to_s } }
      end

      def object_persisted
        wrap { select(&:object_persisted?) }
      end

      def not_object_persisted
        wrap { reject(&:object_persisted?) }
      end

      def latest
        last
      end

      #----------------------------------------------------------------
      #                      Persistence / Commit
      #----------------------------------------------------------------

      #
      # Applies all log entries which were marked as object persisted
      # The log entry itself decides whether it is actually executed or not.
      #
      def apply!
        object_persisted.each(&:apply!)
      end

      #
      # Tells each log entry to enqueue for persisting.
      # The individual log entries may decided whether they actually want
      # to be persisted or not.
      #
      def enqueue_for_persisting!
        each(&:enqueue_for_persisting!)
      end

      #----------------------------------------------------------------
      #                      Wrapped Array Methods
      #----------------------------------------------------------------

      def reverse(*)
        wrap { super }
      end

      def sort(*)
        wrap { super }
      end

      private

      def wrap(&block)
        self.class.new(yield)
      end
    end
  end
end
