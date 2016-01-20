module Petra
  module Proxies
    class ActiveRecordRelationProxy < ObjectProxy
      CLASS_NAMES = %w(ActiveRecord::Relation).freeze

      def to_a
        handle_missing_method(:to_a) + transaction.objects.created(proxied_object.klass)
      end

      delegate :to_ary, :to => :to_a

    end
  end
end
