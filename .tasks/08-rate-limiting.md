# Rate Limiting

## Status
Partial — simple rate-limit middleware exists; standalone limiter algorithms, Redis store, reset headers, and distributed support remain open.

## Problem
No protection against abuse. A single client can overwhelm the service with requests.

## Goal
Add configurable rate limiting per client/IP/key.

## Tasks

### 1. Rate Limiter Core
- [ ] Create `LePain::RateLimiter`
- [ ] Algorithms: fixed window, sliding window, token bucket
- [ ] Thread-safe implementation

### 2. Storage Backends
- [ ] Memory store (single instance)
- [ ] Redis store (distributed)
- [ ] Interface for custom stores

### 3. Middleware Integration
```ruby
router.use do |request, context|
  client_id = context.auth || request.headers['x-forwarded-for']
  limiter = LePain::RateLimiter.new(
    store: :redis,
    limit: 100,
    window: 60,
  )

  unless limiter.allow?(client_id)
    return LePain::Response.error('rate limited', status: 429)
  end

  nil
end
```

### 4. Headers
- [ ] `X-RateLimit-Limit`
- [ ] `X-RateLimit-Remaining`
- [ ] `X-RateLimit-Reset`
- [ ] `Retry-After` on 429

### 5. Config Support
```yaml
rate_limiting:
  enabled: true
  store: redis
  default:
    limit: 100
    window: 60
  rules:
    - path: '/jobs'
      limit: 10
      window: 60
    - auth: 'admin-key'
      limit: 1000
      window: 60
```

## Acceptance Criteria
- Requests are limited per client
- 429 response includes Retry-After header
- Rate limit headers are present
- Redis store works in distributed mode
