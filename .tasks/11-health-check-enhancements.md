# Health Check Enhancements

## Status
Done — startup/readiness/liveness probes, HTTP endpoints, dependency checks, deadlock liveness checks, and config wiring are implemented.

## Problem
Current health check is basic — just a list of registered checks. Needs startup probes, readiness/liveness separation, and dependency checks.

## Goal
Implement Kubernetes-compatible health checks with startup, readiness, and liveness probes.

## Tasks

### 1. Three Probe Types
- [x] **Startup** — is the service initialized? (initializers loaded)
- [x] **Readiness** — can it accept traffic? (dependencies connected)
- [x] **Liveness** — is it alive? (not deadlocked)

### 2. Dependency Checks
- [x] Database connectivity
- [x] Redis connectivity
- [x] MQ connectivity
- [x] External API health

### 3. Endpoints
```
GET /health/startup   → 200/503
GET /health/readiness → 200/503
GET /health/liveness  → 200/503
GET /health           → aggregate of all
```

### 4. Graceful Degradation
- [x] Readiness fails → stop receiving new traffic
- [x] Liveness fails → restart process
- [x] Startup fails → fail fast on boot

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
