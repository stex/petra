module Petra
  module Proxies
    class ActiveRecordProxy < ObjectProxy

      CLASS_NAMES = %w(ActiveRecord::Base).freeze

    end
  end
end