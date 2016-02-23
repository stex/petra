module Petra

  #----------------------------------------------------------------
  #                     Exception Base classes
  #----------------------------------------------------------------

  # Generic error class wrapping all custom petra exceptions
  class PetraError < StandardError;
  end

  #
  # Error class which accepts an options hash and sets its key/value pairs
  # as instance variables. Inherited classes therefore only have to specify the
  # corresponding attribute readers
  #
  class ExtendedError < PetraError
    def initialize(**options)
      options.each do |k, v|
        instance_variable_set("@#{k}", v)
      end
    end
  end

  # Used whenever a configuration value differs from what petra expects it to be
  class ConfigurationError < PetraError
  end

  # Used for generic errors during transaction persistence
  class PersistenceError < PetraError
  end

  # Thrown when a transaction should be persisted, but is locked by another instance
  class TransactionLocked < PetraError
  end

  class HandlerException < ExtendedError

    def retry!
      fail Petra::Retry
    end

    #
    # Resets the currently active transaction
    # This will stop the transaction execution, so make sure that you wrap
    # important code which has to be executed afterwards in an `ensure`
    #
    def reset_transaction!
      @reset = true
      Petra.transaction_manager.reset_transaction
    end

    #
    # Requests a section rollback on the currently active transaction
    # This will stop the transaction execution, so make sure that you wrap
    # important code which has to be executed afterwards in an `ensure`
    #
    def rollback_transaction!
      @rollback = true
      Petra.transaction_manager.rollback_transaction
    end

    alias_method :rollback!, :rollback_transaction!
    alias_method :reset!, :reset_transaction!

    def continue!
      fail Petra::ContinuationError, 'The transaction processing cannot be resumed.' unless continuable?
      @continuation.call
    end

    def continuable?
      false
    end

    protected

    def continuation?
      !!@continuation
    end
  end

  class ValueComparisonError < HandlerException
    attr_reader :object # The affected proxy
    attr_reader :attribute # The affected attribute
    attr_reader :external_value # The new external attribute value

    #
    # Tells the current transaction to ignore further errors of this kind
    # until the attribute value is changed again externally.
    #
    # @param [Boolean] update_value
    #   If set to +true+, the read set entry for this attribute is updated with the
    #   new external value. This means that the new value will be visible inside of
    #   the transaction until it changes again.
    #
    #   Otherwise, the exception is completely ignored and will have no impact
    #   on the values displayed inside the transaction.
    #
    def ignore!(update_value: false)
      Petra.current_transaction.current_section.log_read_integrity_override(object,
                                                                            attribute:      attribute,
                                                                            external_value: external_value,
                                                                            update_value:   update_value)
    end

    def continuable?
      !@reset && !@rollback
    end
  end

  # Thrown when a read attribute changed its value externally
  # If we read AND changed the attribute, a ReadWriteIntegrityError is raised instead
  class ReadIntegrityError < ValueComparisonError
    attr_reader :last_read_value # The value we last read for this attribute (before it was changed)
  end

  # Thrown when an attribute that we previously read AND changed
  # was also changed externally.
  class WriteClashError < ValueComparisonError
    attr_reader :our_value

    #
    # Tells the transaction to ignore all changes previously done to the current
    # attribute in the transaction.
    #
    def undo_changes!
      Petra.current_transaction.current_section.log_attribute_change_veto(object,
                                                                          attribute:      attribute,
                                                                          external_value: external_value)
    end

    alias_method :their_value, :external_value
    alias_method :use_ours!, :ignore!
    alias_method :use_theirs!, :undo_changes!
  end

  #----------------------------------------------------------------
  #                  Transaction Flow Error Classes
  #----------------------------------------------------------------

  # Used internally when a lock could not be acquired (non-suspending locking)
  class LockError < HandlerException
    attr_reader :lock_type
    attr_reader :lock_name

    def initialize(lock_type: 'general', lock_name: 'general', processed: false)
      @lock_type = lock_type
      @lock_name = lock_name
      @processed = processed
    end

    def processed?
      @processed
    end
  end

  class ControlFlowException < PetraError
  end

  # This error is thrown only to tell the transaction manager to
  # abort the current transaction's execution.
  # This is necessary e.g. after successfully committing a transaction
  class AbortTransaction < ControlFlowException;
  end

  # An error class which is never passed on out of petra.
  # It is used to cause a rollback for the currently active petra transaction
  class Rollback < ControlFlowException;
  end

  # See +Rollback+, this error class is used to trigger a complete
  # reset on the currently active petra transaction
  # TODO: Nested transactions anyone?
  class Reset < ControlFlowException
  end

  class Retry < ControlFlowException
  end

end
