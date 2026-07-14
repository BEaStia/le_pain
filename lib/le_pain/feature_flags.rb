# frozen_string_literal: true

require 'digest'

module LePain
  module FeatureFlags
    class Flag
      attr_reader :name, :enabled, :strategy, :config

      def initialize(name:, enabled: false, strategy: :boolean, config: {})
        @name = name
        @enabled = enabled
        @strategy = strategy
        @config = config
      end

      def evaluate(context = {})
        return false unless @enabled

        case @strategy
        when :boolean
          true
        when :percentage
          evaluate_percentage(context)
        when :user_targeted
          evaluate_user_targeted(context)
        when :time_based
          evaluate_time_based(context)
        else
          false
        end
      end

      private

      def evaluate_percentage(context)
        percentage = @config[:percentage] || @config['percentage'] || 0
        seed = @config[:seed] || @config['seed'] || :random

        value = if seed == :random
                  rand
                elsif context[seed]
                  # Deterministic hash based on seed value
                  Digest::MD5.hexdigest("#{@name}:#{context[seed]}").to_i(16) % 100 / 100.0
                else
                  rand
                end

        value < (percentage / 100.0)
      end

      def evaluate_user_targeted(context)
        users = @config[:users] || @config['users'] || []
        user_id = context[:user_id] || context['user_id']

        return false unless user_id

        users.include?(user_id)
      end

      def evaluate_time_based(context)
        enable_at = @config[:enable_at] || @config['enable_at']
        disable_at = @config[:disable_at] || @config['disable_at']

        now = Time.now

        if enable_at
          enable_time = enable_at.is_a?(String) ? Time.parse(enable_at) : enable_at
          return false if now < enable_time
        end

        if disable_at
          disable_time = disable_at.is_a?(String) ? Time.parse(disable_at) : disable_at
          return false if now > disable_time
        end

        true
      end
    end

    class Registry
      def initialize
        @flags = {}
      end

      def register(flag)
        @flags[flag.name] = flag
      end

      def get(name)
        @flags[name.to_s]
      end

      def enabled?(name, context = {})
        flag = get(name)
        return false unless flag

        flag.evaluate(context)
      end

      def all
        @flags.values
      end

      def names
        @flags.keys
      end

      def clear
        @flags.clear
      end

      def to_h
        @flags.transform_values do |flag|
          {
            enabled: flag.enabled,
            strategy: flag.strategy,
            config: flag.config
          }
        end
      end
    end

    class << self
      def registry
        @registry ||= Registry.new
      end

      def register(name, enabled: false, strategy: :boolean, config: {})
        flag = Flag.new(name: name.to_s, enabled: enabled, strategy: strategy, config: config)
        registry.register(flag)
        flag
      end

      def enabled?(name, context = {})
        registry.enabled?(name, context)
      end

      def get(name)
        registry.get(name)
      end

      def all
        registry.all
      end

      def clear
        registry.clear
      end

      def load_from_config(config)
        features = config['features'] || config[:features] || {}

        features.each do |name, flag_config|
          enabled = flag_config['enabled'] || flag_config[:enabled] || false
          strategy = (flag_config['strategy'] || flag_config[:strategy] || :boolean).to_sym
          config_hash = flag_config.reject { |k, _| %w[enabled strategy].include?(k.to_s) }

          register(name, enabled: enabled, strategy: strategy, config: config_hash)
        end
      end
    end
  end
end
