# Metrics & Observability

## Status
Done — thread-safe registry, Counter/Gauge/Histogram/Summary, built-in metrics, Prometheus endpoint, auth/config support, runtime metrics, and custom metrics API are implemented and covered by specs.

## Problem
No visibility into service health beyond logs. Can't track latency, error rates, throughput, or queue depth.

## Goal
Add Prometheus-compatible metrics and expose them via `/metrics` endpoint.

## Tasks

### 1. Metrics Registry
- [x] Create `LePain::Metrics::Registry`
- [x] Support metric types: Counter, Gauge, Histogram, Summary
- [x] Thread-safe implementation

### 2. Built-in Metrics
- [x] `http_requests_total` (counter, labels: method, path, status)
- [x] `http_request_duration_seconds` (histogram, labels: method, path)
- [x] `mq_messages_total` (counter, labels: topic, status)
- [x] `mq_message_duration_seconds` (histogram, labels: topic)
- [x] `active_jobs` (gauge)
- [x] `job_duration_seconds` (histogram, labels: type)

### 3. `/metrics` Endpoint
- [x] Auto-register route when metrics enabled
- [x] Prometheus text exposition format
- [x] Configurable: enable/disable, auth token

### 4. Custom Metrics API
```ruby
LePain::Metrics.counter('orders_created_total', 'Total orders created')
LePain::Metrics.histogram('order_processing_seconds', 'Order processing time')
LePain::Metrics.gauge('queue_depth', 'Pending messages in queue')
```

### 5. Config Support
```yaml
metrics:
  enabled: true
  port: 3002
  auth_token: secret123  # optional
```

## Acceptance Criteria
- `/metrics` returns valid Prometheus format
- All built-in metrics are tracked automatically
- Custom metrics can be registered and queried
- Thread-safe under concurrent load
