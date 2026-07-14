# Configuration Hot Reload

## Status
Partial — file watcher and reload callbacks exist; schema validation, atomic swap, rollback, feature flag/auth reload, and reload attempt limits remain open.

## Problem
Changing config requires service restart. In production, restarts cause downtime and lost in-flight requests.

## Goal
Add ability to reload configuration without restarting the service.

## Tasks

### 1. File Watcher
- [ ] Watch `config/le_pain.yml` for changes
- [ ] Validate new config before applying
- [ ] Atomic config swap (no partial state)

### 2. Reloadable Components
- [ ] Logger level/format
- [ ] Rate limiting rules
- [ ] Circuit breaker thresholds
- [ ] Feature flags
- [ ] Auth headers

### 3. API Endpoint
```
POST /config/reload  → 200 { reloaded: [...], failed: [...] }
GET  /config         → current config (secrets masked)
```

### 4. Safety Guards
- [ ] Validate config schema before applying
- [ ] Rollback on validation failure
- [ ] Log all config changes
- [ ] Max reload attempts limit

### 5. Config Support
```yaml
hot_reload:
  enabled: true
  watch_interval: 5  # seconds
  reloadable:
    - logger
    - rate_limiting
    - circuit_breakers
```

## Acceptance Criteria
- Config changes apply without restart
- Invalid configs are rejected safely
- Reload is logged and auditable
- Non-reloadable settings are clearly documented
