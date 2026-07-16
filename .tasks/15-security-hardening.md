# Security Hardening

## Status
Done — security headers, payload/content-type limits, SQL/XSS/path traversal guards, TLS transport configuration, env/Vault/AWS secret providers, and tamper-evident audit logging are implemented.

## Problem
No built-in security features beyond basic auth header extraction. Missing common security protections.

## Goal
Add security middleware and best practices out of the box.

## Tasks

### 1. Security Headers
- [x] `X-Content-Type-Options: nosniff`
- [x] `X-Frame-Options: DENY`
- [x] `X-XSS-Protection: 1; mode=block`
- [x] `Strict-Transport-Security`
- [x] `Content-Security-Policy`

### 2. Input Sanitization
- [x] SQL injection prevention in payloads
- [x] XSS sanitization in string fields
- [x] Path traversal prevention
- [x] Max payload size limit

### 3. TLS Support
- [x] HTTPS for HTTP transport
- [x] Certificate configuration
- [x] TLS version enforcement

### 4. Secret Management
- [x] Environment variable substitution in config
- [x] Vault integration
- [x] AWS Secrets Manager support

### 5. Audit Logging
- [x] Log all auth failures
- [x] Log permission changes
- [x] Log sensitive operations
- [x] Tamper-proof audit trail

### 6. Config Support
```yaml
security:
  headers:
    x_frame_options: DENY
    csp: "default-src 'self'"
  payload:
    max_size: 1048576  # 1MB
    allowed_types: [application/json]
  tls:
    enabled: true
    cert: /path/to/cert.pem
    key: /path/to/key.pem
```

## Acceptance Criteria
- Security headers are present on all responses
- Oversized payloads are rejected
- TLS works with custom certs
- Audit log captures security events
