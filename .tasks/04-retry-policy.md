# Retry Policy for Async Jobs

## Status
Done — retry strategies, async job retry integration, attempt tracking, DLQ APIs, config support, and transient/permanent error classification are implemented and covered by specs.

## Problem
Jobs can fail due to transient errors (network timeout, temporary unavailability). Currently failed jobs stay failed without retry.

## Goal
Add configurable retry policies with exponential backoff and dead letter queue.

## Tasks

### 1. Retry Policy Core
- [x] Create `LePain::RetryPolicy`
- [x] Strategies: fixed, exponential, linear
- [x] Configurable: max_attempts, backoff_base, max_delay, jitter

### 2. Job Integration
- [x] Auto-retry on transient errors
- [x] Skip retry on permanent errors (validation, not found)
- [x] Track attempt count in Task

### 3. Dead Letter Queue
- [x] Move permanently failed jobs to DLQ
- [x] Store in separate TaskStore namespace
- [x] API: `GET /jobs/dead_letter` — list failed jobs
- [x] API: `POST /jobs/dead_letter/:id/retry` — retry specific job

### 4. Config Support
```yaml
async:
  retry:
    max_attempts: 3
    strategy: exponential
    backoff_base: 2
    max_delay: 300
  dead_letter:
    enabled: true
    ttl: 604800  # 7 days
```

### 5. Error Classification
- [x] `LePain::TransientError` — retryable
- [x] `LePain::PermanentError` — not retryable
- [x] Auto-classify common errors (timeout, connection refused)

## Acceptance Criteria
- Jobs retry with exponential backoff
- Failed jobs move to DLQ after max attempts
- DLQ API works for listing and retrying
- Permanent errors skip retry immediately
