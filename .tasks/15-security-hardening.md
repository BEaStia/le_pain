# Security Hardening

## Status
Partial — security headers, payload limit, input sanitizer, and audit logging exist; TLS, secrets management, path traversal, and tamper-proof audit trail remain open.

## Problem
No built-in security features beyond basic auth header extraction. Missing common security protections.

## Goal
Add security middleware and best practices out of the box.

## Tasks

### 1. Security Headers
- [ ] `X-Content-Type-Options: nosniff`
- [ ] `X-Frame-Options: DENY`
- [ ] `X-XSS-Protection: 1; mode=block`
- [ ] `Strict-Transport-Security`
- [ ] `Content-Security-Policy`

### 2. Input Sanitization
- [ ] SQL injection prevention in payloads
- [ ] XSS sanitization in string fields
- [ ] Path traversal prevention
- [ ] Max payload size limit

### 3. TLS Support
- [ ] HTTPS for HTTP transport
- [ ] Certificate configuration
- [ ] TLS version enforcement

### 4. Secret Management
- [ ] Environment variable substitution in config
- [ ] Vault integration
- [ ] AWS Secrets Manager support

### 5. Audit Logging
- [ ] Log all auth failures
- [ ] Log permission changes
- [ ] Log sensitive operations
- [ ] Tamper-proof audit trail

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
