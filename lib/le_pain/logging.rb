# frozen_string_literal: true

require 'logger'
require 'socket'
require_relative 'logging/json_formatter'

module LePain
  module Logging
    LEVELS = {
      debug: Logger::DEBUG,
      info: Logger::INFO,
      warn: Logger::WARN,
      error: Logger::ERROR,
      fatal: Logger::FATAL,
    }.freeze

    class StructuredLogger < Logger
      attr_accessor :default_level, :transport_levels

      def add(severity, message = nil, progname = nil)
        severity ||= UNKNOWN
        return true if severity < effective_level

        if message.nil?
          if block_given?
            message = yield
          else
            message = progname
            progname = nil
          end
        end

        @logdev&.write(format_message(format_severity(severity), Time.now, progname, message))
        true
      end

      LEVELS.each_key do |level_name|
        define_method(level_name) do |message = nil, extra: nil, **fields, &block|
          payload = structured_message(message, extra, fields, &block)
          add(LEVELS[level_name], payload)
        end
      end

      private

      def effective_level
        transport = Context.current&.transport&.to_sym
        transport_levels.fetch(transport, default_level || level)
      end

      def structured_message(message, extra, fields)
        message = yield if block_given?
        return message if extra.nil? && fields.empty?

        {
          message: message,
          extra: (extra || {}).merge(fields),
        }
      end
    end

    class << self
      def build_logger(config = {})
        config = symbolize_keys(config)
        level = LEVELS[config.fetch(:level, :info).to_sym] || Logger::INFO
        output = resolve_output(config.fetch(:output, 'stdout'))
        format = config.fetch(:format, 'text').to_sym
        transport_levels = normalize_transport_levels(config[:transport_levels] || config[:levels] || {})

        logger = StructuredLogger.new(output)
        logger.default_level = level
        logger.transport_levels = transport_levels
        logger.level = ([level] + transport_levels.values).min || level
        logger.formatter = build_formatter(format)
        logger
      end

      def build_formatter(format)
        case format
        when :json
          JsonFormatter.new
        else
          ->(severity, datetime, _progname, msg) { "[#{datetime}] #{severity}: #{msg}\n" }
        end
      end

      def resolve_output(target)
        return target if target.respond_to?(:write)

        case target.to_s.downcase
        when 'stdout'
          STDOUT
        when 'stderr'
          STDERR
        else
          File.open(target, 'a')
        end
      end

      def normalize_transport_levels(levels)
        symbolize_keys(levels).transform_values { |value| LEVELS[value.to_sym] || Logger::INFO }
      end

      def symbolize_keys(value)
        case value
        when Hash
          value.each_with_object({}) do |(key, nested), result|
            result[key.to_sym] = symbolize_keys(nested)
          end
        else
          value
        end
      end
    end
  end
end
