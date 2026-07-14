# Event Sourcing Support

## Status
Open — no dedicated event store, projections, replay, snapshots, or event publishing implementation found.

## Problem
Some domains need full audit trail and state reconstruction. Current framework doesn't support event sourcing patterns.

## Goal
Add event sourcing primitives: event store, aggregate roots, projections.

## Tasks

### 1. Event Store
- [ ] Create `LePain::EventStore`
- [ ] Append-only event log
- [ ] Event types with schemas
- [ ] Stream per aggregate

### 2. Aggregate Root
```ruby
class Order < LePain::Aggregate
  def create(user_id:, items:)
    apply OrderCreated.new(user_id: user_id, items: items)
  end

  def on_order_created(event)
    @user_id = event.user_id
    @items = event.items
    @status = 'created'
  end
end
```

### 3. Projections
- [ ] Build read models from events
- [ ] Async projection updates
- [ ] Rebuild projections from scratch

### 4. Integration
- [ ] Event publishing via MQ
- [ ] Event replay for debugging
- [ ] Snapshot support for large aggregates

### 5. Config Support
```yaml
event_store:
  type: postgres
  options:
    connection_string: postgres://...
  snapshot_interval: 100
```

## Acceptance Criteria
- Events are appended atomically
- Aggregates reconstruct state from events
- Projections update asynchronously
- Event replay produces same state
