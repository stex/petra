module Petra
  class Transaction
    def self.start(&block)
      yield
    end
  end
end
