# frozen_string_literal: true

module LePain
  # Environment class used to describe current environment
  class Environment
    def self.populate_environments(envs)
      envs.each do |(env, _)|
        define_method("#{env}?") do
          @env_name == env
        end
      end
    end

    def initialize(envs)
      @env_name = if ENV.key?('APP_ENV')
                    ENV['APP_ENV']
                  else
                    default_env = envs.find do |(_env, config)|
                      config.to_h.fetch('default') { false }
                    end
                    raise EnvironmentNotSetError unless default_env

                    default_env[0]
                  end
    end

    def to_s
      @env_name
    end
  end
end
