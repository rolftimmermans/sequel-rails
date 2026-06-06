# frozen_string_literal: true

module SequelRails
  module Railties
    module TestDatabases # :nodoc:
      if ActiveSupport.respond_to?(:parallelize_test_databases)
        require "tempfile"
        require "sequel_rails/storage"
        require "active_support/testing/parallelization"

        ActiveSupport::Testing::Parallelization.after_fork_hook do |i|
          # On macOS, libpq's TCP connection path logs through the os_log subsystem while
          # establishing a connection. After fork, os_log's per-process state is invalid in
          # the child and the first connection segfaults inside _os_log_preferences_refresh.
          # Disabling os_log activity tracing avoids this.
          ENV["OS_ACTIVITY_MODE"] = "disable"

          # Contstruct a worker-specific db config.
          base_config = SequelRails.configuration.environments[Rails.env.to_s]
          base_database = base_config["database"]

          db_config = base_config.except("url").merge("database" => "#{base_database}_#{i}")

          Kernel.silence_warnings do
            SequelRails::Storage.drop_environment(db_config)

            # Attempt to create a database from a template (postgres only) if supported,
            # otherwise create an empty database and load the schema into it.
            if base_config.respond_to?(:template)
              # Clone the parent database. This is faster and ensures OIDs and other
              # database-level state is identical.
              db_config.merge!("template" => base_database, "maintenance_db" => "postgres")
              SequelRails::Storage.create_environment(db_config)
            else
              # Create a blank worker database and load the schema into it.
              SequelRails::Storage.create_environment(db_config)
              filename = SequelRails::Storage.structure_path
              SequelRails::Storage.load_environment(db_config, filename)
            end
          end

          # Model classes capture their database object when they are defined, so
          # every already-loaded model references the boot-time database object.
          # Update the reference to the worker database.
          db = Sequel::Model.db

          # TODO: Ideally the logic below is captured in a reconnect() method on the db.
          db.disconnect
          db.opts[:database] = db_config["database"]

          # Re-initialize extensions with the new database connection.
          db.instance_variable_get(:@loaded_extensions).each do |ext|
            ::Sequel::Database::EXTENSIONS[ext].call(db)
          end
        end
      end
    end
  end
end
