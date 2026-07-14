# Circuit Breaker

## Status
Partial — core circuit breaker states and tests exist; integrations with HTTP/MQ/TaskStore/database and operational metrics/alerts remain open.

## Problem
External service calls (DB, APIs, MQ) can hang or fail, cascading failures across the system.

## Goal
Add circuit breaker pattern to prevent cascading failures and enable graceful degradation.

## Tasks

### 1. Circuit Breaker Core
- [ ] Create `LePain::CircuitBreaker`
- [ ] States: closed → open → half-open → closed
- [ ] Configurable: failure threshold, timeout, success threshold
- [ ] Thread-safe state transitions

### 2. Integration Points
- [ ] Wrap HTTP outbound calls
- [ ] Wrap MQ publish operations
- [ ] Wrap TaskStore operations (Redis)
- [ ] Wrap database connections

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
- [ ] Log state transitions
- [ ] Expose circuit state via `/metrics`
- [ ] Alert on open circuits

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
