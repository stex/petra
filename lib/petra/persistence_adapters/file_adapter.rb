# frozen_string_literal: true

require 'petra/persistence_adapters/adapter'
require 'yaml'

module Petra
  module PersistenceAdapters
    class FileAdapter < Adapter

      #----------------------------------------------------------------
      #                        Configuration
      #----------------------------------------------------------------

      # TODO: change this to use e.g. the field accessors
      class << self
        def storage_directory
          ::Pathname.new(@storage_directory || '/tmp/petra')
        end

        attr_writer :storage_directory
      end

      def persist!
        return true if queue.empty?

        # We currently only allow entries for one transaction in the queue
        with_transaction_lock(queue.first.transaction_identifier) do
          while (entry = queue.shift) do
            identifier = create_entry_file(entry)
            entry.mark_as_persisted!(identifier)
          end
        end
      end

      def transaction_identifiers
        # Wait until no other transaction is doing stuff that might lead to inconsistent data
        with_global_lock do
          ensure_directory_existence('transactions')
          storage_file_name('transactions').children.select(&:directory?).map(&:basename).map(&:to_s)
        end
      end

      def savepoints(transaction)
        with_transaction_lock(transaction.identifier) do
          return [] unless File.exist? storage_file_name('transactions', transaction.identifier)
          storage_file_name('transactions', transaction.identifier).children.select(&:directory?).map do |f|
            ::YAML.load_file(f.join('information.yml').to_s)[:savepoint]
          end
        end
      end

      def log_entries(section)
        with_transaction_lock(section.transaction.identifier) do
          section_dir = storage_file_name(*section_dirname(section))

          # If the given section has never been persisted before, we don't have to
          # search further for log entries
          return [] unless section_dir.exist?

          section_dir.children.select { |f| f.extname == '.entry' }.map do |f|
            entry_hash = ::YAML.load_file(f.to_s)
            Petra::Components::LogEntry.from_hash(section, entry_hash)
          end
        end
      end

      #
      # Removes everything that was persisted while executing the given transaction
      #
      def reset_transaction(transaction)
        with_transaction_lock(transaction) do
          if storage_file_name('transactions', transaction.identifier).exist?
            FileUtils.rm_r(storage_file_name('transactions', transaction.identifier))
          end
        end
      end

      def with_global_lock(**options, &block)
        with_file_lock('global.persistence', **options, &block)
      rescue Petra::LockError => e
        raise e if e.processed?
        exception = Petra::LockError.new(lock_type: 'global', lock_name: 'global.persistence', processed: true)
        raise exception, 'The global lock could not be acquired.'
      end

      def with_transaction_lock(transaction, **options, &block)
        identifier = transaction.is_a?(Petra::Components::Transaction) ? transaction.identifier : transaction
        with_file_lock("transaction.#{identifier}", **options, &block)
      rescue Petra::LockError => e
        raise e if e.processed?
        exception = Petra::LockError.new(lock_type: 'transaction', lock_name: identifier, processed: true)
        raise exception, "The transaction lock '#{identifier}' could not be acquired."
      end

      def with_object_lock(proxy, **options, &block)
        key = proxy.__object_key.gsub(/[^a-zA-Z0-9]/, '-')
        with_file_lock("proxy.#{key}", **options, &block)
      rescue Petra::LockError => e
        raise e if e.processed?
        exception = Petra::LockError.new(lock_type: 'object', lock_name: proxy.__object_key, processed: true)
        raise exception, "The object lock '#{proxy.__object_id}' could not be acquired."
      end

      private

      #
      # The Ruby version of `mkdir -p`
      #
      # @param [*Array] path
      #   The path to the directory in a format #storage_file_name understands
      #
      def ensure_directory_existence(*path)
        FileUtils.mkdir_p(storage_file_name(*path))
      end

      #
      # Executes the given block after acquiring a lock on the given filename
      # If the lock is already held by this process, but not with the same file handle,
      # the function will not try to acquire it again.
      #
      # @param [String] filename
      #
      # @param [Boolean] suspend
      #   If set to +false+, a LockError is thrown if the lock could not be acquired.
      #
      # @raise [Petra::LockError] If +suspend+ is set to +false+ and the lock could not be acquired
      #
      # TODO: sanitize file names
      #
      def with_file_lock(filename, suspend: true)
        Thread.current[:__petra_file_locks] ||= []
        lock_held = Thread.current[:__petra_file_locks].include?(lock_file_name(filename).to_s)

        return yield if lock_held

        File.open(lock_file_name(filename), File::RDWR | File::CREAT, 0644) do |f|
          if suspend
            f.flock(File::LOCK_EX)
          else
            unless f.flock(File::LOCK_EX | File::LOCK_NB)
              Petra.logger.debug "#{Thread.current.name}: Could not acquire '#{filename}'", :red
              fail Petra::LockError
            end
          end

          Petra.logger.debug "#{Thread.current.name}: Acquired Lock: #{filename}", :purple

          Thread.current[:__petra_file_locks] << lock_file_name(filename).to_s

          begin
            yield
          ensure
            # Should be done automatically when the file handle is closed, but who knows
            f.flock(File::LOCK_UN)
            Petra.logger.debug "#{Thread.current.name}: Released Lock: #{filename}", :cyan
            Thread.current[:__petra_file_locks].delete(lock_file_name(filename).to_s)
          end
        end
      end

      #
      # Builds the path to a given file based on the configured storage directory
      #
      # @example STORAGE_DIR/oompa/loompa
      #   storage_file_name('oompa', 'loompa')
      #
      def storage_file_name(*parts)
        self.class.storage_directory.join(*parts)
      end

      #
      # @param [String] filename
      #
      # @return [String] the path to a lockfile with the given name
      #
      def lock_file_name(filename)
        # Make sure the locks directory actually exists
        ensure_directory_existence('locks')
        storage_file_name('locks', "petra.#{filename}.lock")
      end

      #
      # Opens a file within the storage directory and yields its handle
      #
      def with_storage_file(*parts, mode: 'r', perm: 0644, &block)
        File.open(storage_file_name(*parts), mode, perm, &block)
      end

      #
      # Creates a directory for the given section.
      # This includes an `information.yml` file within the directory
      # which contains information about the current savepoint and transaction
      #
      # @param [Petra::Components::Section] section
      #
      def add_section_directory(section)
        dir = section_dirname(section)
        ensure_directory_existence(*dir)

        # If there is already a section directory/information file, we are done.
        return if storage_file_name(*dir, 'information.yml').exist?

        section_hash = {transaction_identifier: section.transaction.identifier,
                        savepoint:              section.savepoint,
                        savepoint_version:      section.savepoint_version}
        with_storage_file(*dir, 'information.yml', mode: 'w') do |f|
          ::YAML.dump(section_hash, f)
        end
      end

      #
      # Creates a file for the given LogEntry.
      # It contains the necessary information to deserialize it later.
      #
      # These files are placed within a section directory (/transaction/section/entry)
      #
      # @param [Petra::Components::LogEntry] entry
      #
      def create_entry_file(entry)
        add_section_directory(entry.section)
        t = Time.now
        filename = "#{t.to_i}.#{t.nsec}.entry"
        with_storage_file(*section_dirname(entry.section), filename, mode: 'w') do |f|
          ::YAML.dump(entry.to_h(entry_identifier: filename), f)
        end
        filename
      end

      #
      # @return [Array<String>] The directory name components for the given section within STORAGE_DIR
      #
      def section_dirname(section)
        ['transactions', section.transaction.identifier, section.savepoint_version.to_s]
      end
    end
  end
end
