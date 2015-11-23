require 'petra/engine'

module Petra

  #----------------------------------------------------------------
  #                        Configuration
  #----------------------------------------------------------------

  #
  # @return [Class] the persistence adapter class used for storing transaction values.
  #   Defaults to use to the cache adapter
  #
  def self.persistence_adapter_class
    "Petra::PersistenceAdapters::#{@@persistence_adapter_class || 'Cache'}".camelize.constantize
  end

  #
  # 
  #
  def self.persistence_adapter_class=(klass)
    @@persistence_adapter_class = "Petra::PersistenceAdapters::#{klass}".camelize.constantize.to_s
  rescue NameError => e
    fail "The adapter class name 'klass' is not valid (#{e})."
  end

end
