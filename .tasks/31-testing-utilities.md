# Testing Utilities

## Status
Done — request/context builders, expressive matchers, schema matcher, in-memory test server, mock MQ client, isolated task store helper, fixture loader, and concurrent request tests are implemented.

## Problem
Testing LePain services requires manual setup of requests, contexts, and assertions. No test helpers provided.

## Goal
Add testing utilities for fast, isolated unit and integration tests.

## Tasks

### 1. Test Helpers
```ruby
require 'le_pain/test'

RSpec.describe OrderHandler do
  include LePain::Test::Helpers

  it 'creates an order' do
    response = dispatch('POST:/orders', body: { user_id: '123' })
    expect(response).to be_success
    expect(response.body[:order_id]).to be_present
  end

  it 'handles MQ messages' do
    response = dispatch_mq('orders.created', { user_id: '123' })
    expect(response).to be_success
  end
end
```

### 2. Request Builders
- [x] `build_http_request(method, path, body:, headers:)`
- [x] `build_mq_request(topic, message, metadata:)`
- [x] `build_context(transport:, auth:, trace_id:)`

### 3. Assertion Helpers
- [x] `expect(response).to be_success`
- [x] `expect(response).to have_status(201)`
- [x] `expect(response).to include_body(key: value)`
- [x] `expect(response).to match_schema(:order)`

### 4. Test Server
- [x] In-memory HTTP server for integration tests
- [x] Mock MQ client
- [x] Isolated task store per test

### 5. Fixture Support
```yaml
# spec/fixtures/orders.yml
valid_order:
  user_id: "user-123"
  items: ["item-a", "item-b"]

invalid_order:
  user_id: null
  items: []
```

## Acceptance Criteria
- Tests run without external dependencies
- Request/response builders are intuitive
- Assertions are expressive
- Test server handles concurrent requests
