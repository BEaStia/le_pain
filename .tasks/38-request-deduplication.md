# Request Deduplication

## Status
Open — idempotency support exists, but no content-hash request deduplication, dedup response headers, TTL window, or dedup metrics implementation found.

## Problem
Clients sometimes send duplicate requests (network retries, UI double-clicks). Processing duplicates wastes resources and causes data issues.

## Goal
Detect and drop duplicate requests before they reach handlers.

## Tasks

### 1. Deduplication Logic
- [ ] Hash request content (method + path + body)
- [ ] Track seen hashes with TTL
- [ ] Return cached response for duplicates
- [ ] Configurable dedup window

### 2. Integration
```ruby
router.deduplicate(
  window: 60,           # 60 second dedup window
  key: ->(req) { "#{req.action}:#{req.payload.hash}" },
  store: :redis,        # or :memory
)
```

### 3. Response Caching
- [ ] Cache successful responses
- [ ] Include original headers
- [ ] Add `X-Deduplicated: true` header

### 4. Metrics
- [ ] Dedup hit rate
- [ ] Memory usage
- [ ] False positive rate

### 5. Config Support
```yaml
deduplication:
  enabled: true
  window: 60
  store: redis
  exclude:
    - 'POST:/webhooks'  # webhooks should always process
    - 'POST:/payments'  # idempotency handles this
```

## Acceptance Criteria
- Duplicate requests return cached response
- Dedup window is configurable
- Memory store evicts old entries
- Excluded paths are not deduplicated
