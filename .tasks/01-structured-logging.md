# Structured Logging

## Status
Done — JSON/text formats, context injection, `extra:` fields, config support, transport-specific levels, and automatic request/response logging with masking are implemented and covered by specs.

## Problem
Current logger uses plain text format. Hard to parse in production log aggregators (ELK, Datadog, CloudWatch).

## Goal
Add JSON-formatted structured logging with automatic context injection.

## Tasks

### 1. Add JSON Formatter
- [x] Create `LePain::Logger::JsonFormatter`
- [x] Include: timestamp, level, message, request_id, trace_id, transport, duration
- [x] Support both `text` and `json` formats via config

### 2. Context Injection
- [x] Auto-inject `request_id`, `trace_id`, `correlation_id` from `Context.current`
- [x] Add `logger.info("msg", extra: { key: value })` support
- [x] Merge extra fields into JSON output

### 3. Config Support
```yaml
logger:
  level: debug
  format: json
  output: stdout  # or /path/to/file.log
```

### 4. Log Levels per Transport
- [x] Allow different log levels for different transports
- [x] Example: HTTP → info, MQ → debug

### 5. Request/Response Logging
- [x] Auto-log incoming requests and outgoing responses
- [x] Include: method, path, status, duration, transport
- [x] Configurable: log body, log headers, mask sensitive fields

## Acceptance Criteria
- `format: json` produces valid JSON lines
- `format: text` produces human-readable output (current behavior)
- All log entries include `request_id` when available
- Tests for both formats
