# Health Check Enhancements

## Status
Partial — startup/readiness/liveness probe objects exist; HTTP endpoints, concrete dependency checks, and deadlock/degradation behavior remain open.

## Problem
Current health check is basic — just a list of registered checks. Needs startup probes, readiness/liveness separation, and dependency checks.

## Goal
Implement Kubernetes-compatible health checks with startup, readiness, and liveness probes.

## Tasks

### 1. Three Probe Types
- [ ] **Startup** — is the service initialized? (initializers loaded)
- [ ] **Readiness** — can it accept traffic? (dependencies connected)
- [ ] **Liveness** — is it alive? (not deadlocked)

### 2. Dependency Checks
- [ ] Database connectivity
- [ ] Redis connectivity
- [ ] MQ connectivity
- [ ] External API health

### 3. Endpoints
```
GET /health/startup   → 200/503
GET /health/readiness → 200/503
GET /health/liveness  → 200/503
GET /health           → aggregate of all
```

### 4. Graceful Degradation
- [ ] Readiness fails → stop receiving new traffic
- [ ] Liveness fails → restart process
- [ ] Startup fails → fail fast on boot

### 5. Config Support
```yaml
health_check:
  enabled: true
  port: 3001
  startup_timeout: 30
  readiness:
    - database
    - redis
    - kafka
  liveness:
    - deadlock_check
```

## Acceptance Criteria
- Three separate endpoints return correct status
- Dependency checks timeout gracefully
- Readiness fails when dependencies are down
- Liveness detects deadlocks
