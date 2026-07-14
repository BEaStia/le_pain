# Request/Response Transformation

## Status
Done — declarative request/response transformers, conditional matching, chain ordering, and built-in transformers are implemented and tested.

## Problem
External services send data in different formats. Manual transformation in handlers is repetitive.

## Goal
Add declarative request/response transformation pipeline.

## Tasks

### 1. Request Transformers
```ruby
router.transform_request do |req|
  # Normalize date formats
  req.payload['created_at'] = Time.parse(req.payload['created_at']) if req.payload['created_at']

  # Flatten nested objects
  req.payload['address'] = req.payload.dig('location', 'address')

  # Type coercion
  req.payload['quantity'] = req.payload['quantity'].to_i
end
```

### 2. Response Transformers
```ruby
router.transform_response do |resp|
  # Add common fields
  resp.body['api_version'] = 'v2'
  resp.body['timestamp'] = Time.now.iso8601

  # Mask sensitive data
  resp.body['user']&.delete('password_hash')

  # Rename fields for client compatibility
  resp.body['orderId'] = resp.body.delete('order_id')
end
```

### 3. Conditional Transformations
- [x] Apply by path pattern
- [x] Apply by transport type
- [x] Apply by content type
- [x] Chain multiple transformers

### 4. Built-in Transformers
- [x] `snake_to_camel` / `camel_to_snake`
- [x] `mask_fields(:email, :phone)`
- [x] `remove_null_fields`
- [x] `add_timestamps`

## Acceptance Criteria
- Transformations apply automatically
- Conditional transformers skip correctly
- Built-in transformers work out of box
- Chain order is predictable
