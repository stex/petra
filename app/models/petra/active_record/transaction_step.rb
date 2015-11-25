module Petra
  module ActiveRecord
    class TransactionStep < ::ActiveRecord::Base
      belongs_to :petra_transaction, :class_name => 'Petra::ActiveRecord::Transaction'
    end
  end
end
