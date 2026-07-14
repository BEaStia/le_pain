# Chaos Engineering Support

## Status
Open — no failure injection middleware, chaos endpoints, safety controls, or resilience metrics implementation found.

## Problem
Systems fail in unexpected ways. Need to test resilience proactively before production incidents.

## Goal
Add chaos engineering primitives to inject failures and test resilience.

## Tasks

### 1. Failure Injection
- [ ] Random HTTP errors (500, 502, 503)
- [ ] Random latency injection
- [ ] Random timeout injection
- [ ] Random MQ message loss
- [ ] Random task store failures

### 2. Chaos Rules
```yaml
chaos:
  enabled: true
  environment: staging  # never in production by default
  rules:
    - name: latency_injection
      type: latency
      probability: 0.05
      delay_ms: 5000
      target: 'POST:/orders'

    - name: error_injection
      type: error
      probability: 0.01
      status: 503
      target: '*'

    - name: circuit_breaker_test
      type: circuit_breaker
      target: 'payment-service'
      failure_rate: 0.8
```

### 3. Control API
- [ ] `POST /chaos/enable` — enable chaos
- [ ] `POST /chaos/disable` — disable chaos
- [ ] `GET /chaos/status` — current chaos rules
- [ ] `POST /chaos/rules` — update rules

### 4. Safety
- [ ] Require explicit enable per environment
- [ ] Kill switch endpoint
- [ ] Audit log of all chaos actions
- [ ] Auto-disable after N minutes

### 5. Metrics
- [ ] Failure injection count
- [ ] System resilience score
- [ ] Recovery time after failure

## Acceptance Criteria
- Failures are injected per rules
- Chaos can be disabled instantly
- Audit log captures all actions
- Metrics track resilience
