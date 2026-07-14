# frozen_string_literal: true

module LePain
  class ConfigValidator
    def self.validate(config)
      errors = []
      errors << 'environments section is missing' unless config.key?('environments')

      envs = config['environments']
      return errors if envs.nil? || envs.empty?

      has_default = envs.values.any? { |v| v.is_a?(Hash) && v['default'] }
      errors << 'no default environment specified' unless has_default

      errors
    end

    def self.validate!(config)
      errors = validate(config)
      raise ConfigurationError, errors.join('; ') unless errors.empty?
    end
  end
end
