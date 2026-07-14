# Compression Middleware

## Status
Done — gzip and Brotli response compression, request decompression, negotiation, thresholding, config, and metrics are implemented and tested.

## Problem
Large request/response payloads waste bandwidth and increase latency. No built-in compression support.

## Goal
Add automatic request/response compression.

## Tasks

### 1. Response Compression
- [x] Gzip compression
- [x] Brotli compression
- [x] Respect `Accept-Encoding` header
- [x] Minimum size threshold (don't compress tiny responses)

### 2. Request Decompression
- [x] Auto-decompress `Content-Encoding: gzip`
- [x] Auto-decompress `Content-Encoding: br`
- [x] Reject unsupported encodings

### 3. Configuration
```yaml
compression:
  enabled: true
  algorithms: [gzip, br]
  min_size: 1024  # bytes
  content_types:
    - application/json
    - text/plain
    - application/xml
```

### 4. Metrics
- [x] Compression ratio
- [x] Bytes saved
- [x] Compression time

## Acceptance Criteria
- Responses are compressed when client supports it
- Compressed requests are decompressed correctly
- Small responses are not compressed
- Compression ratio is tracked
