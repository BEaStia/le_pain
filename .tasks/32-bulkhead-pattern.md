# Bulkhead Pattern

## Status
Open — no bulkhead abstraction, dependency-specific pools, queueing, rejection policy, or bulkhead metrics implementation found.

## Problem
A failing dependency can exhaust all resources (threads, connections), bringing down the entire service.

## Goal
Isolate resources per dependency to prevent cascading failures.

## Tasks

### 1. Bulkhead Core
- [ ] Create `LePain::Bulkhead`
- [ ] Separate thread pools per dependency
- [ ] Configurable max concurrent calls
- [ ] Queue for pending calls

### 2. Integration Points
- [ ] HTTP client calls
- [ ] Database queries
- [ ] MQ operations
- [ ] External API calls

### 3. Usage
```ruby
bulkhead = LePain::Bulkhead.new(
  name: 'payment-service',
  max_concurrent: 10,
  max_queue: 50,
)

bulkhead.execute do
  PaymentService.charge(order_id, amount)
end
```

### 4. Metrics
- [ ] Active concurrent calls
- [ ] Queue depth
- [ ] Rejected calls count
- [ ] Wait time in queue

### 5. Config Support
```yaml
bulkheads:
  payment-service:
    max_concurrent: 10
    max_queue: 50
  inventory-service:
    max_concurrent: 20
    max_queue: 100
```

## Acceptance Criteria
- Dependencies are isolated
- Queue rejects when full
- Metrics are exposed
- Rejected calls fail fast
