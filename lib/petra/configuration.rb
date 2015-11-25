module Petra
  class Configuration
    #
    # @return [Class] the persistence adapter class used for storing transaction values.
    #   Defaults to use to the cache adapter
    #
    def persistence_adapter_class
      (@persistence_adapter_class ||= 'Petra::PersistenceAdapters::Cache').camelize.constantize
    end

    #
    # Sets the adapter to be used as transaction persistence adapter.
    #
    # Currently, the only options are "Cache" and "ActiveRecord"
    #
    def persistence_adapter_class=(klass)
      @persistence_adapter_class = "Petra::PersistenceAdapters::#{klass}".camelize.constantize.to_s
    rescue NameError => e
      fail "The adapter class name 'klass' is not valid (#{e})."
    end
  end
end