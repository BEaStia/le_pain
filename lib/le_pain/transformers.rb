# frozen_string_literal: true

require 'time'

module LePain
  module Transformers
    FILTERED = '[FILTERED]'

    class << self
      def snake_to_camel
        ->(target, *) { replace_data(target, transform_keys(data_for(target)) { |key| camelize(key) }) }
      end

      def camel_to_snake
        ->(target, *) { replace_data(target, transform_keys(data_for(target)) { |key| underscore(key) }) }
      end

      def mask_fields(*fields, replacement: FILTERED)
        names = fields.flat_map { |field| field_names(field.to_s) }.uniq
        ->(target, *) { mask_data(data_for(target), names, replacement) }
      end

      def remove_null_fields
        ->(target, *) { replace_data(target, remove_nulls(data_for(target))) }
      end

      def add_timestamps(field: 'timestamp', clock: -> { Time.now })
        lambda do |target, *|
          data = data_for(target)
          data[field.to_s] = clock.call.iso8601
          target
        end
      end

      private

      def data_for(target)
        if target.respond_to?(:payload)
          target.payload
        elsif target.respond_to?(:body)
          target.body
        else
          target
        end
      end

      def replace_data(target, data)
        if target.respond_to?(:payload)
          target.instance_variable_set(:@payload, data)
        elsif target.respond_to?(:body)
          target.instance_variable_set(:@body, data)
        end
        target
      end

      def transform_keys(value, &block)
        case value
        when Hash
          value.each_with_object({}) do |(key, nested), transformed|
            transformed[yield(key.to_s)] = transform_keys(nested, &block)
          end
        when Array
          value.map { |nested| transform_keys(nested, &block) }
        else
          value
        end
      end

      def mask_data(value, fields, replacement)
        case value
        when Hash
          value.each do |key, nested|
            value[key] = fields.include?(key.to_s) ? replacement : mask_data(nested, fields, replacement)
          end
        when Array
          value.each { |nested| mask_data(nested, fields, replacement) }
        end
        value
      end

      def remove_nulls(value)
        case value
        when Hash
          value.each_with_object({}) do |(key, nested), compacted|
            cleaned = remove_nulls(nested)
            compacted[key] = cleaned unless cleaned.nil?
          end
        when Array
          value.map { |nested| remove_nulls(nested) }.reject(&:nil?)
        else
          value
        end
      end

      def camelize(value)
        first, *rest = value.split('_')
        first + rest.map(&:capitalize).join
      end

      def underscore(value)
        value.gsub(/([A-Z])/, '_\1').downcase.sub(/\A_/, '')
      end

      def field_names(value)
        [value, camelize(value), underscore(value)]
      end
    end
  end
end
