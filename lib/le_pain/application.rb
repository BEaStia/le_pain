# frozen_string_literal: true

require 'uri'
require 'logger'
require 'yaml'
require_relative 'environment'
require_relative 'config_validator'
require_relative 'shutdown_handler'
require_relative 'health_check'
require_relative 'router'
require_relative 'request'
require_relative 'response'
require_relative 'transports'
require_relative 'transports/http'
require_relative 'security'

module LePain
  class Application
    class << self
      attr_writer :env, :health_check, :router

      def env
        if @env
          @env
        else
          envs = config['environments']
          ConfigValidator.validate!(config)
          LePain::Environment.populate_environments(envs)
          @env ||= LePain::Environment.new(envs)
        end
      end

      def root
        @root ||= File.join(File.dirname(__FILE__), '..')
      end

      def config
        @config ||= Security.resolve_secrets(YAML.load_file(File.join(root, 'config', 'le_pain.yml')))
      end

      def logger
        unless @logger
          logger_config = config.fetch('logger', {})
          @logger = Logging.build_logger(logger_config)
        end
        @logger
      end

      def health_check
        @health_check ||= HealthCheck.new
      end

      def router
        @router ||= Router.new.tap do |r|
          auth_config = config.dig('auth', 'header')
          auth_headers = config.dig('auth', 'headers')
          r.configure_request_logging(config.dig('logger', 'request') || {})

          if auth_headers
            r.auth_headers(*auth_headers)
          elsif auth_config
            r.auth_header(auth_config)
          end

          configure_security_middleware(r)
        end
      end

      def enable_async_processing
        return if @async_enabled

        configure_async_processing
        @async_enabled = true
        router.route('POST:/jobs') { |req, ctx| AsyncHandler.handle_request(req, ctx) }
        router.route('GET:/jobs') { |req, ctx| AsyncHandler.handle_request(req, ctx) }
        router.route('GET:/jobs/dead_letter') { |req, ctx| AsyncHandler.handle_request(req, ctx) }
        router.route('POST:/jobs/dead_letter/:id/retry') { |req, ctx| AsyncHandler.handle_request(req, ctx) }
        router.route('GET:/jobs/:id') { |req, ctx| AsyncHandler.handle_request(req, ctx) }
      end

      def enable_metrics
        return if @metrics_enabled

        MetricsHandler.auth_token = config.dig('metrics', 'auth_token')
        configure_circuit_breakers
        @metrics_enabled = true
        router.route('GET:/metrics') { |req, ctx| MetricsHandler.handle_request(req, ctx) }
      end

      def task_store
        @task_store ||= begin
          store_config = config.dig('task_store', 'type') || :memory
          store_options = config.dig('task_store', 'options') || {}
          store = TaskStores.resolve(store_config, **symbolize_options(store_options))
          AsyncHandler.task_store = store
          store
        end
      end

      def configure_async_processing
        retry_config = config.dig('async', 'retry') || {}
        AsyncHandler.retry_policy = RetryPolicy.new(
          max_attempts: (retry_config['max_attempts'] || 3).to_i,
          strategy: (retry_config['strategy'] || :exponential).to_sym,
          base_delay: (retry_config['backoff_base'] || retry_config['base_delay'] || 1.0).to_f,
          max_delay: (retry_config['max_delay'] || 60.0).to_f,
          jitter: retry_config.fetch('jitter', true)
        )

        dead_letter_config = config.dig('async', 'dead_letter') || {}
        return if dead_letter_config['enabled'] == false

        store_type = dead_letter_config['type'] || :memory
        store_options = dead_letter_config['options'] || {}
        store_options = store_options.merge('ttl' => dead_letter_config['ttl']) if dead_letter_config['ttl']
        AsyncHandler.dead_letter_store = TaskStores.resolve(store_type, **symbolize_options(store_options))
      end

      def configure_circuit_breakers
        CircuitBreaker.configure(config['circuit_breakers'] || {})
      end

      def configure_security_middleware(router)
        security_config = config.fetch('security', {})
        return if security_config['enabled'] == false

        headers = normalize_security_headers(security_config.fetch('headers', {}))
        payload = security_config.fetch('payload', {})
        sanitizer = security_config.fetch('sanitizer', {})
        audit = security_config.fetch('audit', {})

        router.middleware(:security_payload_limit, Security::PayloadLimit, **symbolize_options(payload))
        router.middleware(:security_input_sanitizer, Security::InputSanitizer, **symbolize_options(sanitizer))
        router.middleware(:security_audit_log, Security::AuditLog, **symbolize_options(audit))
        router.middleware(:security_headers, Security::SecurityHeaders, **headers)
      end

      def normalize_security_headers(headers)
        normalized = symbolize_options(headers)
        normalized[:content_security_policy] = normalized.delete(:csp) if normalized.key?(:csp)
        normalized
      end

      def symbolize_options(options)
        options.to_h.transform_keys(&:to_sym)
      end

      def configure
        yield self
      end

      def run!(http_port: nil, mq_client: nil, async: false, metrics: false)
        app = new
        app.load
        app.setup_signals

        enable_async_processing if async
        enable_metrics if metrics || config.dig('metrics', 'enabled')

        health_check.start(config.dig('health_check', 'port') || 3001) if config.dig('health_check', 'enabled')

        if http_port
          http_config = config.fetch('http', {})
          http = Transports::HttpAdapter.new(
            router: router,
            host: http_config['host'],
            port: http_port,
            tls: http_config['tls'] || config.dig('security', 'tls')
          )
          http.start
          app.instance_variable_set(:@http, http)
        end

        if mq_client
          mq = Transports::MqAdapter.new(router: router, client: mq_client)
          mq.start
          app.instance_variable_set(:@mq, mq)
        end

        logger.info('system started')
        app.run_loop
      end
    end

    def initialize
      @shutdown_handler = ShutdownHandler.new
      files = Dir.glob(File.join(self.class.root, 'config', 'initializers', '*.rb'))
      files.sort.each { |file| require file }
    end

    def setup_signals
      @shutdown_handler.on_terminate do
        self.class.logger.info('shutting down gracefully...')
        self.class.health_check.stop
        self.instance_variable_get(:@http)&.stop
        self.instance_variable_get(:@mq)&.stop
        teardown
      end
    end

    def load
      files = Dir.glob(File.join(self.class.root, 'config', 'post_initializers', '*.rb'))
      files.sort.each { |file| require file }
    end

    def run_loop
      loop { sleep 0.1 }
    rescue Interrupt
      self.class.logger.info('interrupted')
    end

    def teardown
      self.class.logger.info('teardown complete')
    end
  end
end
