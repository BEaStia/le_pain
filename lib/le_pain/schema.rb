# frozen_string_literal: true

module LePain
  class Schema
    class Field
      attr_reader :name, :type, :required, :items, :description, :enum, :format

      def initialize(name, type, required: true, items: nil, description: nil, enum: nil, format: nil)
        @name = name.to_s
        @type = type
        @required = required
        @items = items
        @description = description
        @enum = enum
        @format = format
      end

      def validate(payload)
        value = payload[@name]
        return [] if value.nil? && !required
        return [Validation::Error.new(field: @name, message: 'is required')] if value.nil?

        errors = []
        errors << Validation::Error.new(field: @name, message: "must be of type #{type}") unless type_valid?(value)
        errors << Validation::Error.new(field: @name, message: "must be one of: #{enum.join(', ')}") if enum && !enum.include?(value)
        errors.concat(validate_array_items(value)) if type == Array && items && value.is_a?(Array)
        errors
      end

      def to_openapi_schema
        schema = type_schema(type)
        schema[:description] = description if description
        schema[:enum] = enum if enum
        schema[:format] = format if format
        schema[:items] = type_schema(items) if type == Array && items
        schema
      end

      private

      def type_valid?(value)
        if type == String
          value.is_a?(String)
        elsif type == Integer
          value.is_a?(Integer)
        elsif type == Float
          value.is_a?(Numeric)
        elsif type == Array
          value.is_a?(Array)
        elsif type == Hash
          value.is_a?(Hash)
        elsif type == :boolean
          [true, false].include?(value)
        elsif type.is_a?(Class)
          type < Schema ? value.is_a?(Hash) && type.validate(value).empty? : value.is_a?(type)
        else
          true
        end
      end

      def validate_array_items(value)
        value.each_with_index.filter_map do |item, index|
          next if Field.new("#{@name}.#{index}", items).send(:type_valid?, item)

          Validation::Error.new(field: "#{@name}.#{index}", message: "must be of type #{items}")
        end
      end

      def type_schema(schema_type)
        if schema_type == String
          { type: 'string' }
        elsif schema_type == Integer
          { type: 'integer' }
        elsif schema_type == Float
          { type: 'number' }
        elsif schema_type == Array
          { type: 'array' }
        elsif schema_type == Hash
          { type: 'object' }
        elsif schema_type == :boolean
          { type: 'boolean' }
        elsif schema_type.is_a?(Class)
          schema_type < Schema ? { '$ref': "#/components/schemas/#{schema_type.schema_name}" } : { type: 'object' }
        else
          { type: 'string' }
        end
      end
    end

    class << self
      def field(name, type = String, **options)
        fields[name.to_s] = Field.new(name, type, **options)
      end

      def fields
        @fields ||= {}
      end

      def validate(payload)
        payload ||= {}
        fields.values.flat_map { |field| field.validate(payload) }
      end

      def validate!(payload)
        errors = validate(payload)
        raise Validation::ValidationError.new(errors) unless errors.empty?

        true
      end

      def schema_name
        name&.split('::')&.last || object_id.to_s
      end

      def to_openapi_schema
        {
          type: 'object',
          properties: fields.transform_values(&:to_openapi_schema),
          required: fields.values.select(&:required).map(&:name),
        }.compact
      end
    end
  end
end
