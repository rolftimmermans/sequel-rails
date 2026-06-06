require 'sequel_rails/shellwords'
require 'sequel_rails/storage/abstract'
require 'sequel_rails/storage/sqlite'
require 'sequel_rails/storage/mysql'
require 'sequel_rails/storage/mysql2'
require 'sequel_rails/storage/postgres'
require 'sequel_rails/storage/jdbc'

module SequelRails
  module Storage
    def self.structure_path
      ENV['DB_STRUCTURE'] || File.join(Rails.root, 'db', 'structure.sql')
    end

    def self.create_all
      with_local_repositories { |config| create_environment(config) }
    end

    def self.drop_all
      with_local_repositories { |config| drop_environment(config) }
    end

    def self.create_environment(config_or_env)
      adapter_for(config_or_env).create
    end

    def self.drop_environment(config_or_env)
      adapter = adapter_for(config_or_env)
      adapter.close_connections
      adapter.drop
    end

    def self.dump_environment(config_or_env, filename)
      adapter_for(config_or_env).dump(filename)
    end

    def self.load_environment(config_or_env, filename)
      adapter_for(config_or_env).load(filename)
    end

    def self.close_all_connections
      with_all_repositories { |config| close_connections_environment(config) }
    end

    def self.close_connections_environment(config_or_env)
      adapter_for(config_or_env).close_connections
    end

    def self.adapter_for(config_or_env)
      config = if config_or_env.is_a? Hash
                 config_or_env
               else
                 ::SequelRails.configuration.environments[config_or_env.to_s]
               end
      lookup_class(config['adapter']).new config
    end

    def self.parse_url(value)
      URI(value) if value.present?
    rescue ArgumentError
      warn "config url could not be parsed, value was: #{value.inspect}"
    end

    def self.extract_database(config, uri)
      database = config['database']
      database ||= uri.path[1..-1] if uri
      database
    end

    def self.extract_adapter(config, uri)
      adapter = config['adapter']
      adapter ||= uri.scheme if uri
      adapter
    end

    def self.extract_host(config, uri)
      host = config['host']
      host ||= uri.host if uri
      host
    end

    def self.with_local_repositories
      ::SequelRails.configuration.environments.each_value do |config|
        uri = parse_url(config['url'])

        database = extract_database(config, uri)
        adapter = extract_adapter(config, uri)
        host = extract_host(config, uri)

        next if database.blank? || adapter.blank?
        if host.blank? || %w( 127.0.0.1 localhost ).include?(host)
          yield config
        else
          warn "This task only modifies local databases. #{database} is on a remote host."
        end
      end
    end

    def self.with_all_repositories
      ::SequelRails.configuration.environments.each_value do |config|
        uri = parse_url(config['url'])
        database = extract_database(config, uri)
        adapter = extract_adapter(config, uri)

        next if database.blank? || adapter.blank?
        yield config
      end
    end

    def self.lookup_class(adapter)
      raise 'Adapter not specified in config, please set the :adapter key.' unless adapter
      return Jdbc if adapter =~ /jdbc/

      klass_name = adapter.camelize.to_sym
      unless self.const_defined?(klass_name)
        raise "Adapter #{adapter} not supported (#{klass_name.inspect})"
      end

      const_get klass_name
    end
  end
end
