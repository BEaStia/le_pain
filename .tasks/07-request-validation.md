# Request Validation

## Status
Done — handler validation DSL, built-in validators, nested validation, structured error responses, and before_filter integration are implemented and tested.

## Problem
Handlers receive raw payloads without validation. Invalid data causes cryptic errors deep in business logic.

## Goal
Add request validation with clear error messages before handlers execute.

## Tasks

### 1. Validation DSL
```ruby
class OrderHandler < LePain::Handler
  validate 'POST:/orders' do
    required :user_id, type: String
    required :items, type: Array, min_length: 1
    optional :coupon_code, type: String, format: /\A[A-Z0-9]+\z/
    optional :quantity, type: Integer, min: 1, max: 100
  end

  handle 'POST:/orders' do |request, context|
    # request is already validated
  end
end
```

### 2. Built-in Validators
- [x] `required` / `optional`
- [x] Type checks: String, Integer, Float, Boolean, Array, Hash
- [x] Format: regex, email, url, uuid
- [x] Range: min, max, min_length, max_length
- [x] Enum: allow only specific values
- [x] Custom: `->(value) { value.start_with?('ORD-') }`

### 3. Error Response
```json
{
  "status": 400,
  "error": {
    "message": "Validation failed",
    "code": "validation_error",
    "details": [
      { "field": "user_id", "message": "is required" },
      { "field": "items", "message": "must have at least 1 element" }
    ]
  }
}
```

### 4. Integration
- [x] Run validation before `before_filter`
- [x] Return 400 on validation failure
- [x] Skip handler execution on invalid request

## Acceptance Criteria
- Validation errors return 400 with clear messages
- Valid requests pass through to handler
- Custom validators work
- Nested object validation supported
