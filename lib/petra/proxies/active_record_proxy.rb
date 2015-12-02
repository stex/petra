module Petra
  module Proxies
    class ActiveRecordProxy < ObjectProxy
      CLASS_NAMES = %w(ActiveRecord::Base).freeze

      delegate :to_model, :to => :proxied_object
    end
  end
end
