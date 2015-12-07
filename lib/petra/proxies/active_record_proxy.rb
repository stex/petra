module Petra
  module Proxies
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

    end
  end
end
