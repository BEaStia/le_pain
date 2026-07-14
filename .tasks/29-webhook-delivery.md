# Webhook Delivery

## Status
Open — no webhook subscription, signed delivery, retry tracking, delivery API, or event filtering implementation found.

## Problem
Services need to notify external systems about events. Manual webhook management is error-prone.

## Goal
Add webhook delivery with retries, signing, and delivery tracking.

## Tasks

### 1. Webhook Registration
```ruby
LePain::Webhooks.register(
  event: 'order.created',
  url: 'https://client.com/webhooks/orders',
  secret: 'whsec_abc123',
  headers: { 'X-Client-Id' => 'client-1' },
)
```

### 2. Delivery Engine
- [ ] POST to webhook URL with signed payload
- [ ] HMAC signature in `X-Webhook-Signature`
- [ ] Retry on failure (exponential backoff)
- [ ] Timeout per delivery

### 3. Delivery Tracking
- [ ] Store delivery attempts
- [ ] Track success/failure rates
- [ ] API: `GET /webhooks/deliveries` — list deliveries
- [ ] API: `POST /webhooks/deliveries/:id/retry` — retry failed

### 4. Event Filtering
- [ ] Filter events by type
- [ ] Filter events by payload conditions
- [ ] Multiple webhooks per event

### 5. Config Support
```yaml
webhooks:
  enabled: true
  default_retries: 3
  default_timeout: 10
  signing:
    algorithm: hmac-sha256
    header: X-Webhook-Signature
  store: postgres
```

## Acceptance Criteria
- Webhooks are delivered reliably
- Signatures are verifiable by receivers
- Failed deliveries are retried
- Delivery history is queryable
