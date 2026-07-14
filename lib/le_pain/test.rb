# frozen_string_literal: true

require 'le_pain'
require 'yaml'

module LePain
  module Test
    class << self
      def schema_registry
        @schema_registry ||= SchemaRegistry.new
      end

      def reset!
        @schema_registry = SchemaRegistry.new
      end
    end

    class SchemaRegistry
      def initialize
        @schemas = {}
      end

      def register(name, schema)
        @schemas[name.to_sym] = normalize_schema(schema)
      end

      def validate(name, value)
        schema = @schemas.fetch(name.to_sym) { raise KeyError, "unknown test schema: #{name}" }
        validate_hash(schema, stringify_keys(value || {}))
      end

      private

      def normalize_schema(schema)
        schema.transform_keys(&:to_s)
      end

      def validate_hash(schema, value)
        schema.all? do |field, rule|
          rule = normalize_rule(rule)
          present = value.key?(field) && !value[field].nil?
          next false if rule[:required] && !present
          next true unless present

          type_matches?(value[field], rule[:type]) &&
            nested_matches?(value[field], rule[:schema])
        end
      end

      def normalize_rule(rule)
        case rule
        when Hash
          rule.transform_keys(&:to_sym)
        when Class, Symbol, String
          { type: rule, required: true }
        else
          { required: true }
        end
      end

      def type_matches?(value, type)
        return true unless type

        case type.to_s.downcase
        when 'string' then value.is_a?(String)
        when 'integer' then value.is_a?(Integer)
        when 'float' then value.is_a?(Float)
        when 'numeric' then value.is_a?(Numeric)
        when 'boolean' then value == true || value == false
        when 'array' then value.is_a?(Array)
        when 'hash' then value.is_a?(Hash)
        else
          type.is_a?(Class) ? value.is_a?(type) : true
        end
      end

      def nested_matches?(value, schema)
        return true unless schema

        value.is_a?(Hash) && validate_hash(normalize_schema(schema), stringify_keys(value))
      end

      def stringify_keys(value)
        value.to_h.transform_keys(&:to_s)
      end
    end

    class TestServer
      attr_reader :router

      def initialize(router: nil)
        @router = router || Router.new
      end

      def route(action, &block)
        router.route(action, &block)
      end

      def register(action, handler_class)
        router.register(action, handler_class)
      end

      def request(method, path, body: {}, headers: {}, context: nil)
        req = Request.from_http(method: method, path: path, body: body, headers: headers)
        ctx = context || Context.new(transport: :http, auth: headers['authorization'])
        router.dispatch(req, context: ctx)
      end

      def get(path, headers: {}, context: nil)
        request('GET', path, headers: headers, context: context)
      end

      def post(path, body: {}, headers: {}, context: nil)
        request('POST', path, body: body, headers: headers, context: context)
      end

      def concurrently(count: 10)
        threads = count.times.map { Thread.new { yield self } }
        threads.map(&:value)
      end
    end

    class MockMqClient
      attr_reader :published, :subscriptions

      def initialize(router: nil)
        @router = router
        @published = []
        @subscriptions = Hash.new { |h, k| h[k] = [] }
      end

      def subscribe(topic, &block)
        @subscriptions[topic] << block
      end

      def publish(topic, message, metadata: {})
        @published << { topic: topic, message: message, metadata: metadata }
        @subscriptions[topic].each { |handler| handler.call(message, metadata) }
        dispatch_to_router(topic, message, metadata) if @router
      end

      private

      def dispatch_to_router(topic, message, metadata)
        request = Request.from_mq(topic: topic, message: message, metadata: metadata)
        context = Context.new(transport: :mq)
        @router.dispatch(request, context: context)
      end
    end

    class FixtureStore
      def initialize(root)
        @root = root
      end

      def load(name)
        path = File.join(@root, "#{name}.yml")
        raise Errno::ENOENT, path unless File.exist?(path)

        YAML.safe_load(File.read(path), permitted_classes: [Symbol], aliases: true) || {}
      end

      def [](name)
        load(name)
      end
    end

    module Helpers
      def dispatch(action, body: {}, headers: {}, metadata: {}, transport: :http)
        request = if transport == :http
                    method, path = action.to_s.split(':', 2)
                    Request.from_http(method: method, path: path, body: body, headers: headers)
                  else
                    Request.from_mq(topic: action.to_s, message: body, metadata: metadata)
                  end

        context = Context.new(
          transport: transport,
          auth: headers['authorization'],
        )

        LePain::Application.router.dispatch(request, context: context)
      end

      def build_http_request(method, path, body: {}, headers: {}, query: {})
        Request.from_http(method: method, path: path, body: body, headers: headers, query: query)
      end

      def build_mq_request(topic, message = {}, metadata: {})
        Request.from_mq(topic: topic, message: message, metadata: metadata)
      end

      def dispatch_http(method, path, body: {}, headers: {})
        dispatch("#{method}:#{path}", body: body, headers: headers, transport: :http)
      end

      def dispatch_mq(topic, message = nil, metadata: {}, **kwargs)
        message = kwargs[:message] if message.nil? && kwargs.key?(:message)
        dispatch(topic, body: message, metadata: metadata, transport: :mq)
      end

      def build_request(action, body: {}, headers: {}, transport: :http)
        if transport == :http
          method, path = action.to_s.split(':', 2)
          Request.from_http(method: method, path: path, body: body, headers: headers)
        else
          Request.from_mq(topic: action.to_s, message: body)
        end
      end

      def build_context(transport: :http, auth: nil, request_id: nil, trace_id: nil)
        Context.new(
          transport: transport,
          auth: auth,
          request_id: request_id,
          trace_id: trace_id,
        )
      end

      def with_context(**attrs)
        ctx = build_context(**attrs)
        Context.with(ctx) { yield ctx }
      end

      def test_server(router: nil)
        TestServer.new(router: router)
      end

      def mock_mq_client(router: nil)
        MockMqClient.new(router: router)
      end

      def isolated_task_store
        TaskStores.resolve(:memory)
      end

      def with_isolated_task_store
        previous_store = AsyncHandler.task_store
        store = isolated_task_store
        AsyncHandler.task_store = store
        yield store
      ensure
        AsyncHandler.task_store = previous_store
      end

      def fixtures(name, root: File.join(Dir.pwd, 'spec', 'fixtures'))
        FixtureStore.new(root).load(name)
      end

      def register_schema(name, schema)
        test_schema_registry.register(name, schema)
      end

      def test_schema_registry
        LePain::Test.schema_registry
      end
    end

    module Matchers
      class BeSuccessMatcher
        def matches?(response)
          response.is_a?(Response) && response.success?
        end

        def description
          'be successful (2xx status)'
        end

        def failure_message
          'expected response to be successful (2xx status)'
        end

        def failure_message_when_negated
          'expected response not to be successful'
        end
      end

      def be_success
        BeSuccessMatcher.new
      end

      class HaveStatusMatcher
        def initialize(status)
          @expected = status
        end

        def matches?(response)
          response.is_a?(Response) && response.status == @expected
        end

        def description
          "have status #{@expected}"
        end

        def failure_message
          "expected response status to be #{@expected}, got #{response&.status}"
        end
      end

      def have_status(status)
        HaveStatusMatcher.new(status)
      end

      class IncludeBodyMatcher
        def initialize(expected)
          @expected = expected
        end

        def matches?(response)
          return false unless response.is_a?(Response)

          @expected.all? { |k, v| response.body[k] == v || response.body[k.to_s] == v }
        end

        def description
          "include body #{@expected}"
        end

        def failure_message
          "expected response body to include #{@expected}, got #{response&.body}"
        end
      end

      def include_body(expected)
        IncludeBodyMatcher.new(expected)
      end

      class MatchSchemaMatcher
        def initialize(name, registry: nil)
          @name = name
          @registry = registry
        end

        def matches?(response)
          return false unless response.is_a?(Response)

          schema_registry.validate(@name, response.body)
        rescue KeyError
          false
        end

        def description
          "match schema #{@name}"
        end

        def failure_message
          "expected response body to match schema #{@name}, got #{response&.body}"
        end

        private

        def schema_registry
          @registry || LePain::Test.schema_registry
        end
      end

      def match_schema(name)
        MatchSchemaMatcher.new(name)
      end

      class HaveValidationErrorsMatcher
        def initialize(fields = nil)
          @fields = fields
        end

        def matches?(response)
          return false unless response.is_a?(Response)
          return false if response.validation_errors.nil? || response.validation_errors.empty?

          return true unless @fields

          error_fields = response.validation_errors.map { |e| e[:field] || e['field'] }
          @fields.all? { |f| error_fields.include?(f.to_s) }
        end

        def description
          @fields ? "have validation errors for #{@fields}" : 'have validation errors'
        end

        def failure_message
          "expected response to have validation errors for #{@fields}, got #{response&.validation_errors}"
        end
      end

      def have_validation_errors(*fields)
        HaveValidationErrorsMatcher.new(fields)
      end
    end
  end
end
