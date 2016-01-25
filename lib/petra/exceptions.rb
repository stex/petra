module Petra

  # Generic error class wrapping all custom petra exceptions
  class PetraError < StandardError; end

  # Used whenever a configuration value differs from what petra expects it to be
  class ConfigurationError < PetraError; end

  # Used for generic errors during transaction persistence
  class PersistenceError < PetraError; end

  # Thrown when a transaction should be persisted, but is locked by another instance
  class TransactionLocked < PetraError; end

  class HandlerException < PetraError
    def reset_transaction!
      raise Petra::Reset
    end

    def rollback_transaction!
      raise Petra::Rollback
    end
  end

  # Thrown when a read (and used) attribute changed its value externally
  class ReadIntegrityError < HandlerException
    attr_reader :object
    attr_reader :attribute

    def initialize(attribute: nil, object: nil)
      @attribute = attribute
      @object    = object
    end

    def reset_object!
      raise Petra::ObjectReset.new(object)
    end
  end

  #----------------------------------------------------------------
  #                     Pseudo error classes
  #----------------------------------------------------------------

  # Used internally when a lock could not be acquired (non-suspending locking)
  class LockError < PetraError
    attr_reader :lock_type
    attr_reader :lock_name

    def initialize(lock_type: 'general', lock_name: 'general')
      @lock_type = lock_type
      @lock_name = lock_name
    end
  end

  # This error is thrown only to tell the transaction manager to
  # abort the current transaction's execution.
  # This is necessary e.g. after successfully committing a transaction
  class AbortTransaction < PetraError; end

  # An error class which is never passed on out of petra.
  # It is used to cause a rollback for the currently active petra transaction
  class Rollback < PetraError; end

  class ObjectReset < PetraError
    attr_reader :object

    def initialize(proxy)
      @object = proxy
    end
  end

  # See +Rollback+, this error class is used to trigger a complete
  # reset on the currently active petra transaction
  # TODO: Nested transactions anyone?
  class Reset < PetraError; end

end
