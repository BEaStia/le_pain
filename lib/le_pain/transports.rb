# frozen_string_literal: true

module LePain
  module Transports
    def self.register(name, adapter)
      @adapters ||= {}
      @adapters[name.to_sym] = adapter
    end

    def self.resolve(name)
      @adapters ||= {}
      adapter = @adapters[name.to_sym]
      raise ConfigurationError, "unknown transport: #{name}" unless adapter

      adapter
    end

    def self.adapters
      @adapters ||= {}
      @adapters.dup
    end
  end
end
