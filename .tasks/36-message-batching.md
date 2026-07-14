# Message Batching

## Status
Open — no batching queue, flush triggers, persistent queue, backpressure, graceful flush, or batching metrics implementation found.

## Problem
Processing messages one-by-one is inefficient for high-throughput scenarios. Batch processing reduces overhead.

## Goal
Add message batching for both consumption and production.

## Tasks

### 1. Batch Consumer
```ruby
class OrderBatchHandler < LePain::BatchHandler
  batch_size 100
  flush_interval 5  # seconds

  handle 'orders.created' do |batch, context|
    # batch is an array of requests
    OrderService.create_bulk(batch.map { |r| r.payload })
  end
end
```

### 2. Batch Producer
```ruby
batch = LePain::Batch.new(max_size: 100, flush_interval: 5)
batch.add(topic: 'orders.created', message: { user_id: '1' })
batch.add(topic: 'orders.created', message: { user_id: '2' })
batch.flush  # or auto-flush
```

### 3. Queue Management
- [ ] In-memory queue
- [ ] Redis-backed queue (persistent)
- [ ] Backpressure when queue is full
- [ ] Graceful flush on shutdown

### 4. Metrics
- [ ] Batch size distribution
- [ ] Flush frequency
- [ ] Queue depth
- [ ] Messages processed per batch

### 5. Config Support
```yaml
batching:
  orders:
    max_size: 100
    flush_interval: 5
    queue_store: memory
  notifications:
    max_size: 500
    flush_interval: 10
    queue_store: redis
```

## Acceptance Criteria
- Messages are batched correctly
- Auto-flush works on interval
- Backpressure prevents OOM
- Graceful flush on shutdown
