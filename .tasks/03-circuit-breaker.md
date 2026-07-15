# Circuit Breaker

## Status
Done — circuit breaker registry/configuration, HTTP client usage, MQ publish wrapping, Redis task store wrapping, metrics, logging, and alert hooks are implemented.

## Problem
External service calls (DB, APIs, MQ) can hang or fail, cascading failures across the system.

## Goal
Add circuit breaker pattern to prevent cascading failures and enable graceful degradation.

## Tasks

### 1. Circuit Breaker Core
- [x] Create `LePain::CircuitBreaker`
- [x] States: closed → open → half-open → closed
- [x] Configurable: failure threshold, timeout, success threshold
- [x] Thread-safe state transitions

### 2. Integration Points
- [x] Wrap HTTP outbound calls
- [x] Wrap MQ publish operations
- [x] Wrap TaskStore operations (Redis)
- [x] Wrap database connections

### 3. Fallback Support
```ruby
breaker = LePain::CircuitBreaker.new(
  name: 'redis',
  failure_threshold: 5,
  timeout: 30,
  fallback: -> { { cached: true, data: {} } },
)
```

### 4. Metrics & Logging
- [x] Log state transitions
- [x] Expose circuit state via `/metrics`
- [x] Alert on open circuits

### 5. Config Support
```yaml
circuit_breakers:
  redis:
    failure_threshold: 5
    timeout: 30
    fallback: null
  kafka:
    failure_threshold: 10
    timeout: 60
```

## Acceptance Criteria
- Circuit opens after N consecutive failures
- Circuit transitions to half-open after timeout
- Circuit closes after M consecutive successes in half-open
- Fallback is called when circuit is open
- State is exposed via metrics
