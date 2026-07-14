# frozen_string_literal: true

require 'json'

module LePain
  module OpenApi
    class Spec
      attr_reader :info, :paths, :components

      def initialize
        @info = {
          title: 'LePain API',
          version: '1.0.0',
          description: 'API documentation',
        }
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
    end

    class RouteDescription
      attr_reader :summary, :description, :tags, :parameters, :request_body, :responses, :security

      def initialize
        @summary = nil
        @description = nil
        @tags = []
        @parameters = []
        @request_body = nil
        @responses = {}
        @security = []
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
        {
          summary: @summary,
          description: @description,
          tags: @tags,
          parameters: @parameters,
          requestBody: @request_body,
          responses: @responses,
          security: @security.empty? ? nil : @security,
        }.compact
      end
    end

    module HandlerDsl
      def describe(action, &block)
        descriptions = @api_descriptions ||= {}
        desc = RouteDescription.new
        desc.instance_exec(&block)
        descriptions[action.to_s] = desc
      end

      def api_descriptions
        @api_descriptions ||= {}
      end
    end

    class Generator
      def initialize(spec: nil)
        @spec = spec || Spec.new
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

          # Create a basic operation if no description exists
          operation = {
            summary: "#{method.upcase} #{path}",
            responses: {
              '200' => { description: 'Success' },
              '404' => { description: 'Not found' },
            },
          }

          # Extract path parameters
          path.scan(/:(\w+)/).each do |param|
            operation[:parameters] ||= []
            operation[:parameters] << {
              name: param[0],
              in: 'path',
              required: true,
              schema: { type: 'string' },
            }
          end

          @spec.add_path(method, path, operation)
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
    end

    class Handler
      def initialize(spec: nil)
        @generator = Generator.new(spec: spec)
      end

      def call(request, context, next_handler)
        case request.action
        when 'GET:/openapi.json'
          spec = @generator.generate_from_router(LePain::Application.router)
          LePain::Response.new(
            status: 200,
            body: spec.to_h,
            headers: { 'Content-Type' => 'application/json' }
          )
        else
          next_handler.call(request, context)
        end
      end
    end
  end
end
