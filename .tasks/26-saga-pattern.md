# Saga Pattern (Distributed Transactions)

## Status
Open — no saga runner, compensation workflow, persisted saga state, resume behavior, or saga metrics implementation found.

## Problem
Microservices need to coordinate multi-step operations that span services. Traditional transactions don't work across services.

## Goal
Add saga pattern support with automatic compensation on failure.

## Tasks

### 1. Saga Definition
```ruby
class CreateOrderSaga < LePain::Saga
  step :reserve_inventory,
    execute: ->(ctx) { InventoryService.reserve(ctx.order_id, ctx.items) },
    compensate: ->(ctx) { InventoryService.release(ctx.order_id, ctx.items) }

  step :charge_payment,
    execute: ->(ctx) { PaymentService.charge(ctx.order_id, ctx.total) },
    compensate: ->(ctx) { PaymentService.refund(ctx.order_id, ctx.total) }

  step :create_order,
    execute: ->(ctx) { OrderService.create(ctx.order_id, ctx.items) },
    compensate: ->(ctx) { OrderService.cancel(ctx.order_id) }
end
```

### 2. Execution Engine
- [ ] Sequential step execution
- [ ] Parallel step execution
- [ ] Automatic compensation on failure
- [ ] Saga state persistence

### 3. State Management
- [ ] Store saga state in TaskStore
- [ ] Resume interrupted sagas
- [ ] Timeout per step
- [ ] Max retry per step

### 4. Monitoring
- [ ] Saga progress tracking
- [ ] Failed saga alerts
- [ ] Compensation success/failure metrics

### 5. Config Support
```yaml
sagas:
  store: postgres
  default_timeout: 300
  max_retries: 3
  compensation_timeout: 60
```

## Acceptance Criteria
- Steps execute in order
- Compensation runs on failure
- Saga state persists across restarts
- Interrupted sagas can resume
