# Background Worker Pool

## Status
Open — async job primitives exist, but no fixed-size worker pool, priority queues, fair scheduling, or worker utilization metrics found.

## Problem
Current async jobs run in unbounded threads. No control over concurrency, priority, or resource usage.

## Goal
Add a managed worker pool with priority queues and resource limits.

## Tasks

### 1. Worker Pool
- [ ] Fixed-size thread pool
- [ ] Configurable pool size per job type
- [ ] Priority queues (high, normal, low)
- [ ] Fair scheduling

### 2. Job Priority
```ruby
class UrgentReportJob < LePain::AsyncJob
  priority :high

  def self.process(task)
    # processed before normal jobs
  end
end
```

### 3. Resource Limits
- [ ] Max memory per worker
- [ ] Max CPU time per job
- [ ] Kill workers exceeding limits
- [ ] Graceful degradation under load

### 4. Monitoring
- [ ] Active worker count
- [ ] Queue depth per priority
- [ ] Job throughput (jobs/sec)
- [ ] Worker utilization

### 5. Config Support
```yaml
async:
  worker_pool:
    size: 10
    max_queue_size: 1000
    priorities:
      high: 3
      normal: 5
      low: 2
    limits:
      max_memory_mb: 512
      max_cpu_seconds: 300
```

## Acceptance Criteria
- Workers respect pool size limits
- High priority jobs processed first
- Resource limits are enforced
- Queue depth is monitored
