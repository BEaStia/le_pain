# frozen_string_literal: true

module LePain
  module Validation
    FORMATS = {
      email: /\A[^@\s]+@[^@\s]+\.[^@\s]+\z/,
      url: /\Ahttps?:\/\/[^\s]+\z/,
      uuid: /\A[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\z/i,
    }.freeze

    class Error
      attr_reader :field, :message

      def initialize(field:, message:)
        @field = field
        @message = message
      end

      def to_h
        { field: @field, message: @message }
      end
    end

    class ValidationError < StandardError
      attr_reader :errors

      def initialize(errors)
        @errors = errors
        super("Validation failed: #{errors.map { |e| "#{e.field}: #{e.message}" }.join(', ')}")
      end
    end

    class Rule
      attr_reader :field, :type, :required, :format, :min, :max, :min_length, :max_length, :enum, :custom, :validator

      def initialize(field, validator: nil, **options)
        @field = field.to_s
        @validator = validator
        @type = options[:type] || (validator ? Hash : nil)
        @required = options.fetch(:required, true)
        @format = options[:format]
        @min = options[:min]
        @max = options[:max]
        @min_length = options[:min_length]
        @max_length = options[:max_length]
        @enum = options[:enum]
        @custom = options[:custom]
      end

      def validate(value, prefix: nil)
        qualified_field = [prefix, @field].compact.join('.')
        errors = []
        return errors if value.nil? && !@required

        if value.nil? && @required
          errors << Error.new(field: qualified_field, message: 'is required')
          return errors
        end

        return errors if value.nil?

        errors << type_error(qualified_field) unless type_valid?(value)
        errors << format_error(qualified_field) unless format_valid?(value)
        errors << range_error(qualified_field) unless range_valid?(value)
        errors << length_error(qualified_field) unless length_valid?(value)
        errors << enum_error(qualified_field) unless enum_valid?(value)
        errors << custom_error(qualified_field, value) unless custom_valid?(value)
        errors.concat(@validator.validate(value, prefix: qualified_field)) if @validator && type_valid?(value)
        errors.compact
      end

      private

      def type_valid?(value)
        return true unless @type

        case @type
        when String then value.is_a?(String)
        when Integer then value.is_a?(Integer)
        when Float then value.is_a?(Numeric)
        when Array then value.is_a?(Array)
        when Hash then value.is_a?(Hash)
        when :boolean then [true, false].include?(value)
        else value.is_a?(@type)
        end
      end

      def type_error(field)
        Error.new(field: field, message: "must be of type #{@type}")
      end

      def format_valid?(value)
        return true unless @format
        return true unless value.is_a?(String)

        resolved_format.match?(value)
      end

      def format_error(field)
        Error.new(field: field, message: "must match format #{@format.inspect}")
      end

      def resolved_format
        FORMATS.fetch(@format, @format)
      end

      def range_valid?(value)
        return true unless value.is_a?(Numeric)
        return false if @min && value < @min
        return false if @max && value > @max

        true
      end

      def range_error(field)
        msg = []
        msg << "min #{@min}" if @min
        msg << "max #{@max}" if @max
        Error.new(field: field, message: "must be in range (#{msg.join(', ')})")
      end

      def length_valid?(value)
        return true unless value.respond_to?(:length)
        return false if @min_length && value.length < @min_length
        return false if @max_length && value.length > @max_length

        true
      end

      def length_error(field)
        msg = []
        msg << "min length #{@min_length}" if @min_length
        msg << "max length #{@max_length}" if @max_length
        Error.new(field: field, message: "length violation (#{msg.join(', ')})")
      end

      def enum_valid?(value)
        return true unless @enum

        @enum.include?(value)
      end

      def enum_error(field)
        Error.new(field: field, message: "must be one of: #{@enum.join(', ')}")
      end

      def custom_valid?(value)
        return true unless @custom

        @custom.call(value)
      end

      def custom_error(field, value)
        Error.new(field: field, message: "failed custom validation (value: #{value.inspect})")
      end
    end

    class Validator
      def initialize
        @rules = {}
      end

      def required(field, **options, &block)
        @rules[field.to_s] = Rule.new(field, required: true, validator: nested_validator(&block), **options)
      end

      def optional(field, **options, &block)
        @rules[field.to_s] = Rule.new(field, required: false, validator: nested_validator(&block), **options)
      end

      def validate(payload, prefix: nil)
        payload ||= {}
        errors = @rules.flat_map do |field, rule|
          rule.validate(payload[field.to_s], prefix: prefix)
        end

        errors.empty? ? [] : errors
      end

      def validate!(payload)
        errors = validate(payload)
        raise ValidationError.new(errors) unless errors.empty?

        true
      end

      private

      def nested_validator(&block)
        return nil unless block

        self.class.new.tap { |validator| validator.instance_exec(&block) }
      end
    end
  end
end
