# frozen_string_literal: true

require 'le_pain/version'
require 'le_pain/environment'
require 'le_pain/config_validator'
require 'le_pain/shutdown_handler'
require 'le_pain/context'
require 'le_pain/request'
require 'le_pain/response'
require 'le_pain/handler'
require 'le_pain/router'
require 'le_pain/application'

# Task stores (memory always loaded, others lazy)
require 'le_pain/task_stores/base'
require 'le_pain/task_stores/memory_store'
require 'le_pain/task_stores'

Dir[File.join(__dir__, 'tasks/**/*.rake')].each { |ext| load ext }

module LePain
  class EnvironmentNotSetError < StandardError; end
  class ConfigurationError < StandardError; end

  # Lazy loading для всех опциональных модулей
  autoload :Logging, 'le_pain/logging'
  autoload :Metrics, 'le_pain/metrics'
  autoload :MetricsHandler, 'le_pain/metrics_handler'
  autoload :Validation, 'le_pain/validation'
  autoload :HttpClient, 'le_pain/http_client'
  autoload :HttpResponse, 'le_pain/http_client'
  autoload :CircuitBreaker, 'le_pain/circuit_breaker'
  autoload :CircuitOpenError, 'le_pain/circuit_breaker'
  autoload :RetryPolicy, 'le_pain/retry_policy'
  autoload :Middleware, 'le_pain/middleware'
  autoload :Transformers, 'le_pain/transformers'
  autoload :Security, 'le_pain/security'
  autoload :Cache, 'le_pain/cache'
  autoload :OpenApi, 'le_pain/openapi'
  autoload :CLI, 'le_pain/cli'
  autoload :Tracing, 'le_pain/tracing'
  autoload :HealthCheckEnhanced, 'le_pain/health_check_enhanced'
  autoload :Plugin, 'le_pain/plugin'
  autoload :Migrations, 'le_pain/migrations'
  autoload :ConfigHotReload, 'le_pain/config_hot_reload'
  autoload :FeatureFlags, 'le_pain/feature_flags'
  autoload :Idempotency, 'le_pain/idempotency'
  autoload :AsyncJob, 'le_pain/async_job'
  autoload :AsyncHandler, 'le_pain/async_handler'
  autoload :Task, 'le_pain/task'
  autoload :Transports, 'le_pain/transports'
  autoload :Errors, 'le_pain/errors'
end
