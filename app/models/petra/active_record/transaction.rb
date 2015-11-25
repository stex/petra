module Petra
  module ActiveRecord
    class Transaction < ::ActiveRecord::Base
      has_many :transaction_steps, :class_name => 'Petra::ActiveRecord::TransactionStep', :inverse_of => :petra_transaction
    end
  end
end
