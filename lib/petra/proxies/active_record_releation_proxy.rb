module Petra
  module Proxies
    class ActiveRecordRelationProxy < ObjectProxy
      CLASS_NAMES = %w(ActiveRecord::Relation).freeze
    end
  end
end
