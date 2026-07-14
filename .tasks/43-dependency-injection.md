# Dependency Injection Container

## Status
Open — no container API, scoped resolution, auto-wiring, test overrides, lifecycle callbacks, or dependency graph validation implementation found.

## Problem
Hardcoded dependencies make testing difficult and coupling tight. No standard way to manage service dependencies.

## Goal
Add a lightweight DI container for managing service dependencies.

## Tasks

### 1. Container API
```ruby
LePain::Container.register(:db) { Database.new(config) }
LePain::Container.register(:cache) { Redis.new(url) }
LePain::Container.register(:order_service) { OrderService.new(db: resolve(:db), cache: resolve(:cache)) }

# Resolve
db = LePain::Container.resolve(:db)
```

### 2. Scoped Dependencies
- [ ] Singleton (one per app lifetime)
- [ ] Request-scoped (one per request)
- [ ] Transient (new every time)

### 3. Auto-Wiring
```ruby
class OrderHandler < LePain::Handler
  inject :order_service, :cache

  handle 'POST:/orders' do |req, ctx|
    @order_service.create(req.payload)
  end
end
```

### 4. Testing Support
- [ ] Override registrations in tests
- [ ] Mock dependencies easily
- [ ] Isolated containers per test

### 5. Lifecycle
- [ ] `on_start` callbacks
- [ ] `on_stop` callbacks
- [ ] Dependency graph validation

## Acceptance Criteria
- Dependencies are resolved correctly
- Scoped dependencies work as expected
- Auto-wiring injects dependencies
- Test overrides work cleanly
