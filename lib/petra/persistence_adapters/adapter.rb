module Petra
  module PersistenceAdapters

    #
    # This class acts as an interface and specifies the methods that
    # a transaction adapter has to implement.
    #
    class Adapter

      #
      # Persists the transaction steps which happened after
      # the last changes were persisted.
      #
      def persist!
        not_implemented
      end

      #
      # Adds the given log entry to the queue to be persisted next.
      # Fails if the queue already contains the log entry.
      #
      # @todo: Check previous sections? How to uniquely identify a log entry?
      #
      def enqueue(log_entry)
        if queue.include?(log_entry)
          fail Petra::PersistenceError, 'A log entry can only be added to a persistence queue once'
        end
        queue << log_entry
      end

      #
      # @return [Array<String>] the identifiers of all transactions which are
      #   currently persisted (>= one section finished, but not committed)
      #
      def transaction_identifiers
        not_implemented
      end

      #
      # @param [Petra::Components::Transaction] transaction
      #
      # @return [Array<String>] the names of all savepoints which were previously persisted
      #   for the given transaction
      #
      def savepoints(transaction)
        not_implemented
      end

      #
      # @param [Petra::Components::Section] section
      #
      # @return [Array<Petra::Components::LogEntry>] All log entries which were previously
      #   persisted for the given section
      #
      def log_entries(section)
        not_implemented
      end

      protected

      def ensure_directory_existence(*path)
        FileUtils.mkdir_p(storage_file_name(*path))
      end

      def with_global_lock(&block)
        with_file_lock('global.persistence', &block)
      end

      def with_transaction_lock(transaction_identifier, &block)
        with_file_lock(transaction_identifier, &block)
      end

      def with_file_lock(filename, &block)
        @held_file_locks ||= []
        if @held_file_locks.include?(lock_file_name(filename))
          block.call
        else
          begin
            File.open(lock_file_name(filename), File::RDWR|File::CREAT, 0644) do |f|
              f.flock(File::LOCK_EX)
              @held_file_locks << lock_file_name(filename)
              block.call
            end
          ensure
            @held_file_locks.delete(lock_file_name(filename))
          end
        end
      end

      def storage_file_name(*parts)
        Petra.configuration.storage_directory.join(*parts)
      end

      def lock_file_name(filename)
        # Make sure the locks directory actually exists
        ensure_directory_existence('locks')
        storage_file_name('locks', "petra.#{filename}.lock")
      end

      def with_storage_file(*parts, mode: 'r', perm: 0644, &block)
        File.open(storage_file_name(*parts), mode, perm, &block)
      end

      def queue
        @queue ||= []
      end

      def clear_queue!
        @queue = []
      end

    end
  end
end
