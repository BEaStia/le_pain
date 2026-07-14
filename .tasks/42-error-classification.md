# Error Classification & Handling

## Status
Done — error hierarchy, classification, retry/backoff handling, alert strategies, context enrichment, configurable stack traces, and structured responses are implemented and tested.

## Problem
All errors are treated the same. Different error types need different handling (retry, alert, user message).

## Goal
Add structured error classification with automatic handling strategies.

## Tasks

### 1. Error Hierarchy
```ruby
LePain::Error::Base
├── LePain::ClientError (4xx)
│   ├── BadRequest
│   ├── Unauthorized
│   ├── Forbidden
│   ├── NotFound
│   └── ValidationError
├── LePain::ServerError (5xx)
│   ├── InternalError
│   ├── NotImplemented
│   └── ServiceUnavailable
├── LePain::TransientError (retryable)
│   ├── Timeout
│   ├── ConnectionRefused
│   └── RateLimited
└── LePain::PermanentError (not retryable)
    ├── InvalidState
    └── BusinessRuleViolation
```

### 2. Automatic Handling
- [x] Transient errors → retry with backoff
- [x] Permanent errors → fail immediately, log alert
- [x] Client errors → return to caller
- [x] Server errors → alert ops, return 500

### 3. Error Context
- [x] Attach request context to errors
- [x] Attach stack trace (configurable)
- [x] Attach correlation ID
- [x] Structured error codes

### 4. Error Response Format
```json
{
  "status": 400,
  "error": {
    "code": "validation_error",
    "message": "Invalid payload",
    "details": [...],
    "request_id": "req-001",
    "trace_id": "trace-abc"
  }
}
```

## Acceptance Criteria
- Errors are classified correctly
- Transient errors trigger retries
- Permanent errors skip retries
- Error responses are consistent
