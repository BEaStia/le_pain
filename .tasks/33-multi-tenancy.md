# Multi-Tenancy Support

## Status
Open — no tenant resolver, tenant-scoped stores/cache/feature flags, tenant context injection, or tenant management implementation found.

## Problem
Services need to serve multiple tenants with data isolation and tenant-specific configuration.

## Goal
Add multi-tenancy primitives with automatic tenant context propagation.

## Tasks

### 1. Tenant Context
```ruby
# Extracted from header, subdomain, or payload
tenant = LePain::Tenant.current
tenant.id        # => 'acme'
tenant.name      # => 'Acme Corp'
tenant.plan      # => 'enterprise'
```

### 2. Tenant Resolution
- [ ] Header: `X-Tenant-Id`
- [ ] Subdomain: `acme.api.example.com`
- [ ] JWT claim
- [ ] Payload field

### 3. Data Isolation
- [ ] Tenant-scoped TaskStore
- [ ] Tenant-scoped cache keys
- [ ] Tenant-scoped database queries
- [ ] Tenant-scoped feature flags

### 4. Tenant-Specific Config
```yaml
tenants:
  acme:
    rate_limit: 1000
    features: [new_checkout, dark_mode]
    task_store: redis
  beta:
    rate_limit: 100
    features: [new_checkout]
    task_store: memory
```

### 5. Middleware
- [ ] Auto-resolve tenant from request
- [ ] Reject unknown tenants
- [ ] Inject tenant into context

## Acceptance Criteria
- Tenant is resolved automatically
- Data is isolated per tenant
- Tenant-specific config applies
- Unknown tenants are rejected
