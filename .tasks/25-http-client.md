# HTTP Client with Context Propagation

## Status
Done — HTTP client supports pluggable adapters (`net_http`, `stub`, custom), named service config, context/auth/idempotency propagation, retries, timeouts, circuit breaker integration, request logging, and response parsing.

## Problem
Services need to call other services. Manual header forwarding (trace_id, auth) is error-prone and repetitive.

## Goal
Add an HTTP client that auto-propagates context headers.

## Tasks

### 1. Basic Client
```ruby
client = LePain::HttpClient.new(base_url: 'http://order-service:3000')
resp = client.post('/orders', body: { user_id: '123' })
```

### 2. Context Propagation
- [x] Auto-inject `x-request-id`, `x-trace-id`, `x-correlation-id`
- [x] Auto-forward auth headers
- [x] Auto-inject idempotency keys for retries

### 3. Built-in Resilience
- [x] Retry on transient errors
- [x] Timeout per request
- [x] Circuit breaker integration
- [x] Request logging

### 4. Response Handling
```ruby
resp = client.get('/orders/123')
resp.success?      # => true
resp.status        # => 200
resp.body          # => { ... }
resp.header('x-request-id')
```

### 5. Config Support
```yaml
http_client:
  default_timeout: 5
  max_retries: 2
  follow_redirects: true
  services:
    order-service:
      base_url: http://order-service:3000
      timeout: 10
      retries: 3
```

## Acceptance Criteria
- Context headers are auto-forwarded
- Retries work with exponential backoff
- Timeouts are enforced
- Response is easy to parse
