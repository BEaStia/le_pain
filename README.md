# LePain

A micro framework for building Ruby microservices with **unified sync/async handling**.

Write your business logic once — handle it the same way whether the request comes from HTTP, Kafka, NATS, or RabbitMQ.

## Features

- **Unified Transport** — Same handler for HTTP, Kafka, NATS, RabbitMQ
- **Context Propagation** — request_id, trace_id, correlation_id across services
- **Async Jobs** — Submit tasks, poll status, pluggable storage (Memory, File, SQLite, PostgreSQL, Redis)
- **Idempotency** — Protect against duplicate requests
- **Request Validation** — DSL for validating payloads
- **Error Classification** — Structured errors with automatic retry/alert strategies
- **Circuit Breaker** — Prevent cascading failures
- **Retry Policy** — Exponential backoff with jitter
- **Middleware Pipeline** — Named middlewares with ordering
- **Rate Limiting** — Per-client rate limits
- **Caching** — LRU cache with TTL
- **Feature Flags** — Boolean, percentage, user-targeted, time-based strategies
- **Health Checks** — Kubernetes-style startup/readiness/liveness probes
- **Metrics** — Prometheus-compatible `/metrics` endpoint
- **Distributed Tracing** — OpenTelemetry-compatible spans
- **Security** — Headers, payload limits, input sanitization, audit logging
- **OpenAPI Generation** — Auto-generate specs from routes
- **Plugin System** — Extensible architecture
- **Database Migrations** — PostgreSQL, MySQL, SQLite adapters + Rails compatibility
- **Config Hot Reload** — Reload configuration without restart
- **CLI** — Scaffold services and generate components
- **Testing Utilities** — Helpers and matchers for RSpec

## Installation

```ruby
gem 'le_pain'
```

```bash
$ bundle install
```

## Quick Start

```ruby
require 'le_pain'

class OrderHandler < LePain::Handler
  handle 'POST:/orders' do |request, context|
    order = OrderService.create(
      user_id: request['user_id'],
      items: request['items'],
    )
    LePain::Response.success(order, status: 201)
  end

  handle 'orders.created' do |request, context|
    # Same logic, different transport (MQ)
    order = OrderService.create(
      user_id: request['user_id'],
      items: request['items'],
    )
    LePain::Response.success(order)
  end
end

LePain::Application.router.register('POST:/orders', OrderHandler)
LePain::Application.router.register('orders.created', OrderHandler)

LePain::Application.run!(http_port: 3000)
```

## Architecture

```
┌─────────────┐     ┌─────────────┐     ┌─────────────┐
│   HTTP      │     │   Kafka     │     │   NATS      │
│   Adapter   │     │   Adapter   │     │   Adapter   │
└──────┬──────┘     └──────┬──────┘     └──────┬──────┘
       │                   │                   │
       ▼                   ▼                   ▼
┌─────────────────────────────────────────────────────┐
│                    Request                          │
│         (normalized, transport-agnostic)            │
└──────────────────────┬──────────────────────────────┘
                       │
                       ▼
┌─────────────────────────────────────────────────────┐
│                    Context                          │
│  request_id · trace_id · correlation_id             │
│  idempotency_key · transport · auth · metadata      │
└──────────────────────┬──────────────────────────────┘
                       │
                       ▼
┌─────────────────────────────────────────────────────┐
│                    Router                           │
│  middlewares → auth → idempotency → handler lookup  │
└──────────────────────┬──────────────────────────────┘
                       │
                       ▼
┌─────────────────────────────────────────────────────┐
│                    Handler                          │
│         (business logic, written once)              │
└──────────────────────┬──────────────────────────────┘
                       │
                       ▼
┌─────────────────────────────────────────────────────┐
│                    Response                         │
│         (status · body · error · headers)           │
└─────────────────────────────────────────────────────┘
```

## Core Concepts

### Request

Unified request abstraction. Works the same regardless of transport:

```ruby
# From HTTP
request = LePain::Request.from_http(
  method: 'POST',
  path: '/orders',
  body: { user_id: '123', items: ['a', 'b'] },
  headers: { 'x-request-id' => 'req-001' },
)

# From MQ
request = LePain::Request.from_mq(
  topic: 'orders.created',
  message: { user_id: '123', items: ['a', 'b'] },
  metadata: { request_id: 'req-001' },
)

# Access payload (string keys always)
request['user_id']          # => '123'
request.fetch('items', [])  # => ['a', 'b']
```

### Response

```ruby
LePain::Response.success({ id: 1 }, status: 201)
LePain::Response.error('not found', status: 404)
LePain::Response.bad_request('invalid payload')
LePain::Response.unauthorized
LePain::Response.not_found
```

### Context

Carries request-scoped data through the entire lifecycle:

```ruby
handle 'POST:/orders' do |request, context|
  context.request_id        # => 'req-001'
  context.trace_id          # => 'trace-abc'
  context.correlation_id    # => 'corr-xyz'
  context.transport         # => :http or :mq
  context.auth              # => 'Bearer ...'
  context.idempotency_key   # => 'idem-001'
  context.expired?          # => false
  context.remaining_time    # => 29.5 (seconds)
end
```

**Fiber-local access** — convenient for service layers:

```ruby
class OrderService
  def self.create(attrs)
    context = LePain::Context.current
    logger.info("[#{context.request_id}] creating order")
  end
end
```

### Handler

```ruby
class OrderHandler < LePain::Handler
  # Filters run before every action
  before_filter do |request, context|
    return LePain::Response.unauthorized unless valid_token?(context.auth)
    nil # continue
  end

  handle 'POST:/orders' do |request, context|
    LePain::Response.success({ id: 1 }, status: 201)
  end

  handle 'GET:/orders/:id' do |request, context|
    LePain::Response.success({ id: request['id'] })
  end
end
```

### Router

```ruby
router = LePain::Application.router

# Register handler classes
router.register('POST:/orders', OrderHandler)
router.register('GET:/orders/:id', OrderHandler)

# Register inline handlers
router.route('health') do |request, context|
  LePain::Response.success({ status: 'ok' })
end

# Middleware
router.use do |request, context|
  return LePain::Response.error('rate limited', status: 429) if rate_limited?(request)
  nil # continue
end
```

## Transports

### HTTP

Built-in lightweight HTTP server (zero dependencies):

```ruby
LePain::Application.run!(http_port: 3000)
```

### Message Queues

Adapter pattern for Kafka, NATS, RabbitMQ:

```ruby
# Kafka
kafka = LePain::Transports::KafkaClient.new(
  brokers: ['kafka:9092'],
  group_id: 'orders-service',
)

# NATS
nats = LePain::Transports::NatsClient.new(url: 'nats://nats:4222')

# RabbitMQ
rmq = LePain::Transports::RmqClient.new(url: 'amqp://rabbitmq:5672')

mq = LePain::Transports::MqAdapter.new(router: router, client: kafka)
mq.subscribe('orders.created') { |response| ... }

LePain::Application.run!(http_port: 3000, mq_client: kafka)
```

## Async Jobs

Submit long-running tasks and poll their status:

```ruby
# Define a job
class ReportJob < LePain::AsyncJob
  def self.process(task)
    sleep 5 # heavy work
    { report_url: '/reports/123', rows: 150 }
  end
end

LePain::AsyncHandler.register(ReportJob)
LePain::Application.run!(http_port: 3000, async: true)
```

**API:**

```
POST /jobs              → 201 { id, type, state: "pending", ... }
GET  /jobs/:id          → { id, state: "running", ... }
GET  /jobs/:id          → { id, state: "completed", result: {...}, duration: 5.2 }
GET  /jobs?state=done   → [{...}, {...}]
```

### Task Stores

Pluggable storage for async jobs:

```yaml
# config/le_pain.yml
task_store:
  type: memory          # memory, file, redis, postgres, sqlite
  options:
    ttl: 86400
```

**Memory** (default) — in-memory hash, lost on restart.

**File** — persists to disk:

```yaml
task_store:
  type: file
  options:
    path: /tmp/lepain_tasks
    ttl: 86400
```

**SQLite** — requires `sqlite3` gem:

```yaml
task_store:
  type: sqlite
  options:
    database: ./db/tasks.db  # or ':memory:' for in-memory
    ttl: 86400
```

Perfect for development and small production deployments. No external dependencies, easy setup.

**PostgreSQL** — requires `pg` gem:

```yaml
task_store:
  type: postgres
  options:
    connection_string: postgres://user:pass@localhost/mydb
    pool_size: 5
    ttl: 86400
```

Best for production with high load. Supports indexing and complex queries.

**Redis** — requires `redis` gem:

```yaml
task_store:
  type: redis
  options:
    redis: Redis.new(url: 'redis://localhost:6379')
    ttl: 86400
```

Best for distributed systems with multiple service instances.

## Configuration

### Full Reference

```yaml
# config/le_pain.yml

environments:
  development:
    default: true
  staging:
  production:
  docker:

# ── Logger ──────────────────────────────────────────
logger:
  level: debug                    # debug, info, warn, error
  format: text                    # text, json
  output: stdout                  # stdout, stderr, /path/to/file.log

# ── Context Headers ─────────────────────────────────
context:
  request_id_header: x-request-id
  trace_id_header: x-trace-id
  correlation_id_header: x-correlation-id

# ── Auth ────────────────────────────────────────────
auth:
  header: X-Api-Key               # single header
  # or
  headers: [X-Api-Key, Authorization, X-Auth-Token]  # fallback chain

# ── Idempotency ─────────────────────────────────────
idempotency:
  enabled: true
  ttl: 3600                       # cache lifetime in seconds
  key_header: idempotency-key     # header name

# ── HTTP Transport ──────────────────────────────────
http:
  host: 0.0.0.0
  port: 3000
  max_connections: 100

# ── Task Store (async jobs) ─────────────────────────
task_store:
  type: memory                    # memory, file, redis, postgres, sqlite
  options:
    ttl: 86400
    path: /tmp/lepain_tasks       # for file store
    database: ./db/tasks.db       # for sqlite store
    connection_string: postgres://user:pass@localhost/mydb  # for postgres
    # redis: Redis.new(...)       # for redis store

# ── Feature Flags ───────────────────────────────────
features:
  new_checkout:
    enabled: true
    strategy: boolean
  dark_mode:
    enabled: true
    strategy: percentage
    percentage: 25
    seed: user_id
  beta_feature:
    enabled: true
    strategy: user_targeted
    users: [user-1, user-2]

# ── Config Hot Reload ───────────────────────────────
hot_reload:
  enabled: true
  watch_interval: 5               # seconds
  reloadable_sections: [logger, rate_limiting, circuit_breakers]

# ── Async Jobs ──────────────────────────────────────
async:
  pool_size: 5                    # max concurrent threads
  timeout: 300                    # max job execution time (seconds)

# ── Health Check ────────────────────────────────────
health_check:
  enabled: true
  port: 3001

# ── Shutdown ────────────────────────────────────────
shutdown:
  timeout: 30                     # graceful shutdown timeout (seconds)

# ── Error Handling ──────────────────────────────────
error_handling:
  include_backtrace: false        # include stack traces in error responses
```

### Programmatic Configuration

```ruby
LePain::Application.configure do |app|
  # Router
  app.router.auth_header('X-Api-Token')
  app.router.auth_headers('X-Api-Key', 'Authorization')

  app.router.auth_extractor do |request|
    request.headers['x-custom-auth']
  end

  app.router.idempotency(ttl: 3600, key_extractor: ->(req, ctx) { req['idempotency_key'] })

  # Health checks
  app.health_check.register('database') do
    { connected: true, latency_ms: 5 }
  end

  app.health_check.register('redis') do
    { connected: redis.ping }
  end
end
```

## Idempotency

Protect against duplicate requests from retries:

```ruby
# Enable globally
LePain::Application.router.idempotency(ttl: 300)

# Client sends:
# POST /orders
# Idempotency-Key: unique-key-123
#
# Second request with same key returns cached response
```

## Distributed Tracing

Headers propagate across services:

```
Service A                          Service B
─────────                          ─────────
x-request-id: req-001              x-request-id: req-002
x-trace-id: trace-abc    ───────▶  x-trace-id: trace-abc
x-correlation-id: corr-xyz         x-correlation-id: corr-xyz
```

```ruby
handle 'orders.created' do |request, context|
  # trace_id is the same across all services
  logger.info("[#{context.trace_id}] processing order")
end
```

## Feature Flags

Control feature rollouts with multiple strategies:

```ruby
# Boolean flag
LePain::FeatureFlags.register('new_checkout', enabled: true)

# Percentage rollout
LePain::FeatureFlags.register(
  'dark_mode',
  enabled: true,
  strategy: :percentage,
  config: { percentage: 25, seed: :user_id }
)

# User-targeted
LePain::FeatureFlags.register(
  'beta_feature',
  enabled: true,
  strategy: :user_targeted,
  config: { users: ['user-1', 'user-2'] }
)

# Time-based
LePain::FeatureFlags.register(
  'holiday_sale',
  enabled: true,
  strategy: :time_based,
  config: {
    enable_at: '2024-12-01T00:00:00Z',
    disable_at: '2024-12-31T23:59:59Z'
  }
)

# Check in code
if LePain::FeatureFlags.enabled?('new_checkout', user_id: '123')
  # new logic
else
  # old logic
end
```

Load from config:

```yaml
# config/le_pain.yml
features:
  new_checkout:
    enabled: true
    strategy: boolean
  dark_mode:
    enabled: true
    strategy: percentage
    percentage: 25
    seed: user_id
```

## Error Classification

Structured error handling with automatic strategies:

```ruby
# Error hierarchy
LePain::Errors::ClientError::BadRequest       # 400
LePain::Errors::ClientError::Unauthorized     # 401
LePain::Errors::ClientError::Forbidden        # 403
LePain::Errors::ClientError::NotFound         # 404
LePain::Errors::ClientError::ValidationError  # 422

LePain::Errors::ServerError::InternalError    # 500
LePain::Errors::ServerError::NotImplemented   # 501
LePain::Errors::ServerError::ServiceUnavailable # 503

LePain::Errors::TransientError::Timeout       # 504 (retryable)
LePain::Errors::TransientError::ConnectionRefused # 503 (retryable)
LePain::Errors::TransientError::RateLimited   # 429 (retryable)

LePain::Errors::PermanentError::InvalidState  # 409 (not retryable)
LePain::Errors::PermanentError::BusinessRuleViolation # 422 (not retryable)
```

Automatic handling:

```ruby
handler = LePain::Errors::Handler.new(
  alert_callback: ->(error) { Sentry.capture_exception(error) }
)

begin
  # your code
rescue => e
  classified = handler.handle(e, context: {
    request_id: context.request_id,
    trace_id: context.trace_id
  })

  # Transient errors → logged as warnings (will retry)
  # Server errors → logged as errors + alert callback
  # Client errors → logged as info
end
```

Error response format:

```json
{
  "status": 400,
  "error": {
    "code": "validation_error",
    "message": "Invalid payload",
    "request_id": "req-001",
    "trace_id": "trace-abc",
    "details": [...]
  }
}
```

## Config Hot Reload

Reload configuration without restarting the service:

```ruby
# Start watcher
LePain::ConfigHotReload.start(
  config_path: 'config/le_pain.yml',
  watch_interval: 5,  # seconds
  reloadable_sections: %w[logger rate_limiting circuit_breakers]
)

# Manual reload
LePain::ConfigHotReload.reload

# Callback
LePain::ConfigHotReload.watcher.on_reload do |reloaded, failed|
  puts "Reloaded: #{reloaded.join(', ')}"
  puts "Failed: #{failed.map { |f| f[:section] }.join(', ')}"
end
```

## Plugin System

Extend LePain with plugins:

```ruby
class MyPlugin < LePain::Plugin::Base
  def initialize
    super(name: 'my-plugin', version: '1.0.0')
  end

  def on_initialize(app)
    # Setup code
  end

  def on_start(app)
    # Start background workers
  end

  def on_stop(app)
    # Cleanup
  end
end

# Register plugin
LePain::Plugin.register(MyPlugin.new)

# Lifecycle managed automatically
LePain::Application.run!(http_port: 3000)
```

## Database Migrations

### LePain Migrations

```ruby
class CreateUsers < LePain::Migrations::Migration
  version '001'
  name 'create_users'

  def up(connection)
    adapter = LePain::Migrations::Adapters::PostgresAdapter.new(connection)
    adapter.create_table(:users) do |t|
      t.primary_key :id
      t.string :name, null: false
      t.string :email
      t.timestamps
    end
    adapter.add_index(:users, :email, unique: true)
  end

  def down(connection)
    adapter = LePain::Migrations::Adapters::PostgresAdapter.new(connection)
    adapter.drop_table(:users)
  end
end
```

Supported adapters:
- **PostgresAdapter** - PostgreSQL
- **MySQLAdapter** - MySQL
- **SQLiteAdapter** - SQLite

### Rails Migrations Compatibility

Use existing Rails migrations:

```ruby
# Convert Rails migration to LePain
LePain::Migrations::RailsCompatibility::RailsMigrationConverter.convert(
  'db/migrate/20240101000000_create_users.rb',
  'migrations/001_create_users.rb'
)

# Or run Rails migrations directly via ActiveRecord
runner = LePain::Migrations::RailsCompatibility::RailsMigrationRunner.new(
  adapter: 'postgresql',
  database: 'mydb',
  migrations_path: 'db/migrate'
)

runner.migrate
runner.rollback(steps: 1)
runner.status
```

## Health Check Enhancements

Kubernetes-compatible health probes:

```ruby
health_check = LePain::HealthCheckEnhanced::EnhancedHealthCheck.new

# Startup probe - runs once on boot
health_check.startup do
  { initialized: true }
end

# Readiness probe - checks if service can accept traffic
health_check.readiness(:database) do
  ActiveRecord::Base.connection.active?
end

health_check.readiness(:redis) do
  redis.ping == 'PONG'
end

# Liveness probe - checks if service is alive
health_check.liveness(:process) do
  { alive: true, uptime: Process.clock_gettime(Process::CLOCK_UPTIME) }
end

health_check.start!

# Endpoints
# GET /health/startup   → 200/503
# GET /health/readiness → 200/503
# GET /health/liveness  → 200/503
# GET /health           → aggregate of all
```

## Graceful Shutdown

Handles `SIGTERM` and `SIGINT` automatically:

```ruby
LePain::Application.run!(http_port: 3000)
# On SIGTERM:
#   1. Stop accepting new connections
#   2. Finish in-flight requests
#   3. Run teardown callbacks
#   4. Exit cleanly
```

## Example: Full Microservice

```ruby
require 'le_pain'

# ── Service Layer ──────────────────────────────────
class OrderService
  def self.create(user_id:, items:)
    context = LePain::Context.current
    order_id = SecureRandom.uuid
    logger.info("[#{context.request_id}] order #{order_id} via #{context.transport}")
    { order_id: order_id, user_id: user_id, items: items }
  end
end

# ── Handler ────────────────────────────────────────
class OrderHandler < LePain::Handler
  validate 'POST:/orders' do
    required :user_id, type: String
    required :items, type: Array, min_length: 1
  end

  handle 'POST:/orders' do |request, context|
    order = OrderService.create(
      user_id: request['user_id'],
      items: request['items'],
    )
    LePain::Response.success(order, status: 201)
  end

  handle 'orders.created' do |request, context|
    order = OrderService.create(
      user_id: request['user_id'],
      items: request['items'],
    )
    LePain::Response.success(order)
  end
end

# ── Async Job ──────────────────────────────────────
class ReportJob < LePain::AsyncJob
  def self.process(task)
    sleep 2
    { report_url: '/reports/abc', rows: 150 }
  end
end

# ── Feature Flags ──────────────────────────────────
LePain::FeatureFlags.register(
  'new_checkout',
  enabled: true,
  strategy: :percentage,
  config: { percentage: 50 }
)

# ── Setup ──────────────────────────────────────────
LePain::Application.router.register('POST:/orders', OrderHandler)
LePain::Application.router.register('orders.created', OrderHandler)
LePain::AsyncHandler.register(ReportJob)
LePain::Application.router.idempotency(ttl: 300)

# ── Middleware ─────────────────────────────────────
LePain::Application.router.middleware_pipeline.register(:cors, LePain::Middleware::Cors, allowed_origins: ['*'])
LePain::Application.router.middleware_pipeline.register(:rate_limit, LePain::Middleware::RateLimit, limit: 100, window: 60)

# ── Run ────────────────────────────────────────────
LePain::Application.run!(http_port: 3000, async: true, metrics: true)
```

## CLI

Scaffold new services and generate components:

```bash
# Create new service
lepain new my-service

# Generate components
lepain generate handler order
lepain generate job report
lepain generate service user

# Help
lepain help
lepain version
```

Generated service structure:

```
my-service/
├── Gemfile
├── Rakefile
├── Dockerfile
├── config/
│   └── le_pain.yml
├── handlers/
│   └── example_handler.rb
├── jobs/
│   └── example_job.rb
├── services/
│   └── example_service.rb
├── bin/
│   └── start_service.sh
└── spec/
    └── spec_helper.rb
```

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/beastia/le_pain.

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).
