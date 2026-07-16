# frozen_string_literal: true

require 'json'
require 'yaml'

module LePain
  module OpenApi
    class Spec
      attr_reader :info, :paths, :components

      def initialize(info: nil)
        @info = {
          title: 'LePain API',
          version: '1.0.0',
          description: 'API documentation',
        }.merge((info || {}).transform_keys(&:to_sym))
        @paths = {}
        @components = { schemas: {} }
      end

      def title=(title)
        @info[:title] = title
      end

      def version=(version)
        @info[:version] = version
      end

      def description=(description)
        @info[:description] = description
      end

      def add_path(method, path, operation)
        @paths[path] ||= {}
        @paths[path][method.downcase.to_sym] = operation
      end

      def add_schema(name, schema)
        @components[:schemas][name] = schema
      end

      def to_h
        {
          openapi: '3.0.3',
          info: @info,
          paths: @paths,
          components: @components,
        }
      end

      def to_json
        JSON.pretty_generate(to_h)
      end

      def to_yaml
        YAML.dump(JSON.parse(JSON.generate(to_h)))
      end
    end

    class RouteDescription
      attr_reader :summary, :description, :tags, :parameters, :request_body, :responses, :security

      def initialize(**metadata)
        @contract = metadata.delete(:contract)
        metadata = @contract.metadata.merge(metadata) if @contract
        @summary = metadata[:summary]
        @description = metadata[:description]
        @tags = Array(metadata[:tags])
        @parameters = Array(metadata[:parameters])
        @request_body = metadata[:request_body]
        @params_schema = metadata[:params]
        @query_schema = metadata[:query]
        @headers_schema = metadata[:headers]
        @request_schema = metadata[:request]
        @response_schema = metadata[:response]
        @responses = metadata[:responses] || {}
        @security = Array(metadata[:security])
      end

      def summary=(summary)
        @summary = summary
      end

      def description=(description)
        @description = description
      end

      def tags=(tags)
        @tags = tags
      end

      def add_parameter(name:, in_location:, required: false, schema: {}, description: nil)
        @parameters << {
          name: name,
          in: in_location,
          required: required,
          schema: schema,
          description: description,
        }.compact
      end

      def request_body=(body)
        @request_body = body
      end

      def add_response(status, description:, schema: nil)
        @responses[status] = {
          description: description,
          content: schema ? { 'application/json' => { schema: schema } } : nil,
        }.compact
      end

      def add_security(security)
        @security << security
      end

      def to_operation
        add_response('200', description: 'Success', schema: schema_ref(@response_schema)) if @response_schema && @responses.empty?
        {
          summary: @summary,
          description: @description,
          tags: @tags,
          parameters: operation_parameters,
          requestBody: @request_body || request_body_from_schema,
          responses: normalized_responses,
          security: @security.empty? ? nil : @security,
          'x-le-pain-policies': @contract&.policies&.empty? ? nil : @contract&.policies,
        }.compact
      end

      def schemas
        [@params_schema, @query_schema, @headers_schema, @request_schema, @response_schema]
          .compact
          .select { |schema| schema.respond_to?(:to_openapi_schema) }
      end

      private

      def request_body_from_schema
        return nil unless @request_schema

        {
          required: true,
          content: {
            'application/json' => {
              schema: schema_ref(@request_schema),
            },
          },
        }
      end

      def normalized_responses
        return @responses unless @responses.empty?

        { '200' => { description: 'Success' } }
      end

      def operation_parameters
        parameters = @parameters.dup
        parameters.concat(schema_parameters(@query_schema, 'query'))
        parameters.concat(schema_parameters(@headers_schema, 'header'))
        parameters
      end

      def schema_parameters(schema, location)
        return [] unless schema.respond_to?(:fields)

        schema.fields.values.map do |field|
          {
            name: field.name,
            in: location,
            required: field.required,
            schema: field.to_openapi_schema,
          }
        end
      end

      def schema_ref(schema)
        return nil unless schema

        { '$ref': "#/components/schemas/#{schema.schema_name}" }
      end
    end

    module HandlerDsl
      def describe(action, **metadata, &block)
        descriptions = @api_descriptions ||= {}
        desc = RouteDescription.new(**metadata)
        desc.instance_exec(&block) if block
        descriptions[action.to_s] = desc
      end

      def api_descriptions
        @api_descriptions ||= {}
      end

      def route(method, path, **metadata)
        action = super
        describe(action, **metadata) unless metadata.empty?
        action
      end
    end

    class Generator
      attr_reader :warnings

      def initialize(spec: nil)
        @spec = spec || Spec.new
        @warnings = []
      end

      def generate_from_handlers(handlers)
        handlers.each do |action, handler_class|
          next unless handler_class.respond_to?(:api_descriptions)

          desc = handler_class.api_descriptions[action]
          next unless desc

          method, path = parse_action(action)
          @spec.add_path(method, path, desc.to_operation)
        end

        @spec
      end

      def generate_from_router(router)
        router.routes.each do |action|
          method, path = parse_action(action)
          handler = router.route_handlers[action]
          desc = description_for(action, handler)
          operation = if desc
                        add_schemas(desc)
                        desc.to_operation
                      else
                        @warnings << "Route #{action} is undocumented"
                        fallback_operation(method, path)
                      end

          operation[:parameters] = Array(operation[:parameters]) + path_parameters(path)

          @spec.add_path(method, openapi_path(path), operation)
        end

        @spec
      end

      private

      def parse_action(action)
        if action.include?(':')
          method, path = action.split(':', 2)
          [method.downcase, path]
        else
          ['get', "/#{action}"]
        end
      end

      def description_for(action, handler)
        return handler.api_descriptions[action] if handler.respond_to?(:api_descriptions) && handler.api_descriptions[action]
        return RouteDescription.new(contract: handler.endpoint_contracts[action]) if handler.respond_to?(:endpoint_contracts) && handler.endpoint_contracts[action]

        nil
      end

      def add_schemas(desc)
        desc.schemas.each do |schema|
          @spec.add_schema(schema.schema_name, schema.to_openapi_schema)
        end
      end

      def fallback_operation(method, path)
        {
          summary: "#{method.upcase} #{path}",
          responses: {
            '200' => { description: 'Success' },
            '404' => { description: 'Not found' },
          },
        }
      end

      def path_parameters(path)
        path.scan(/:(\w+)/).map do |param|
          {
            name: param[0],
            in: 'path',
            required: true,
            schema: { type: 'string' },
          }
        end
      end

      def openapi_path(path)
        path.gsub(/:([^\/]+)/, '{\1}')
      end
    end

    class Handler
      def initialize(spec: nil, router: nil, config: nil)
        @spec = spec
        @router = router
        @config = config || {}
      end

      def call(request, context, next_handler)
        case request.action
        when 'GET:/openapi.json'
          respond(body: generated_spec.to_h, content_type: 'application/json')
        when 'GET:/openapi.yaml'
          respond(body: generated_spec.to_yaml, content_type: 'application/yaml')
        when 'GET:/docs'
          respond(body: swagger_ui, content_type: 'text/html')
        when 'GET:/redoc'
          respond(body: redoc_ui, content_type: 'text/html')
        else
          next_handler.call(request, context)
        end
      end

      private

      def generated_spec
        spec = @spec || Spec.new(info: @config['info'])
        Generator.new(spec: spec).generate_from_router(@router || LePain::Application.router)
      end

      def respond(body:, content_type:)
        LePain::Response.new(status: 200, body: body, headers: { 'Content-Type' => content_type })
      end

      def swagger_ui
        <<~HTML
          <!doctype html>
          <html><head><title>Swagger UI</title></head>
          <body>
            <div id="swagger-ui"></div>
            <script src="https://unpkg.com/swagger-ui-dist/swagger-ui-bundle.js"></script>
            <script>SwaggerUIBundle({ url: '/openapi.json', dom_id: '#swagger-ui' });</script>
          </body></html>
        HTML
      end

      def redoc_ui
        <<~HTML
          <!doctype html>
          <html><head><title>ReDoc</title></head>
          <body>
            <redoc spec-url="/openapi.json"></redoc>
            <script src="https://cdn.redoc.ly/redoc/latest/bundles/redoc.standalone.js"></script>
          </body></html>
        HTML
      end
    end
  end
end
