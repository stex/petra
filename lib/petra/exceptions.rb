module Petra

  # Generic error class wrapping all custom petra exceptions
  class PetraError < StandardError; end

  # Used whenever a configuration value differs from what petra expects it to be
  class ConfigurationError < PetraError; end

  #----------------------------------------------------------------
  #                     Pseudo error classes
  #----------------------------------------------------------------

  # Used internally when a lock (pessimistic) could not be acquired
  class LockError < PetraError; end

  # An error class which is never passed on out of petra.
  # It is used to cause a rollback for the currently active petra transaction
  class RollBack < PetraError; end

  # See +Rollback+, this error class is used to perform a commit
  # TODO: See if this could be done using a ".commit" on the block resulting from a transaction instead
  class Commit < PetraError; end

  # See +Rollback+, this error class is used to trigger a complete
  # reset on the currently active petra transaction
  # TODO: Nested transactions anyone?
  class Reset < PetraError; end

end
