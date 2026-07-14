# Caching Layer

## Status
Partial — in-memory cache with TTL, fetch, and basic LRU eviction exists; Redis/Memcached/file stores, tenant prefixes, versioned keys, and tag invalidation remain open.

## Problem
Repeated expensive computations or external calls waste resources. No built-in caching mechanism.

## Goal
Add multi-level caching with context-aware invalidation.

## Tasks

### 1. Cache Interface
```ruby
LePain::Cache.get('user:123')
LePain::Cache.set('user:123', data, ttl: 300)
LePain::Cache.fetch('user:123', ttl: 300) { User.find(123) }
LePain::Cache.delete('user:123')
```

### 2. Storage Backends
- [ ] Memory (LRU eviction)
- [ ] Redis
- [ ] Memcached
- [ ] File-based

### 3. Context-Aware Keys
- [ ] Auto-prefix by tenant/service
- [ ] Include version in key
- [ ] Tag-based invalidation

### 4. Cache-Aside Pattern
```ruby
class OrderService
  extend LePain::Cacheable

  cache :get_order, key: ->(id) { "order:#{id}" }, ttl: 60

  def self.get_order(id)
    # expensive call
  end
end
```

### 5. Config Support
```yaml
cache:
  store: redis
  default_ttl: 300
  max_memory_mb: 256
  namespaces:
    orders: 60
    users: 300
```

## Acceptance Criteria
- Cache hit/miss ratio is trackable
- TTL expiry works correctly
- Memory store evicts LRU items
- Tag-based invalidation works
