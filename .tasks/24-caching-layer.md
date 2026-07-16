# Caching Layer

## Status
Done — memory, Redis, Memcached, and file stores are implemented with TTL, LRU, tenant/service/version key prefixes, tag invalidation, cache-aside helpers, config support, and hit/miss metrics.

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
- [x] Memory (LRU eviction)
- [x] Redis
- [x] Memcached
- [x] File-based

### 3. Context-Aware Keys
- [x] Auto-prefix by tenant/service
- [x] Include version in key
- [x] Tag-based invalidation

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
