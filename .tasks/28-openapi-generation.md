# OpenAPI / Swagger Generation

## Status
Partial — OpenAPI spec builder, route descriptions, router generation, and JSON handler exist; YAML endpoint, Swagger/ReDoc UI, request/response validation, and undocumented-route warnings remain open.

## Problem
API documentation is manual and gets out of sync. Clients need accurate specs for code generation.

## Goal
Auto-generate OpenAPI specs from registered routes and handlers.

## Tasks

### 1. Route Annotations
```ruby
class OrderHandler < LePain::Handler
  describe 'POST:/orders',
    summary: 'Create a new order',
    tags: ['orders'],
    request_body: {
      user_id: { type: 'string', required: true },
      items: { type: 'array', items: { type: 'string' }, required: true },
    },
    responses: {
      201 => { description: 'Order created' },
      400 => { description: 'Invalid request' },
    }

  handle 'POST:/orders' do |req, ctx|
    # ...
  end
end
```

### 2. Spec Generation
- [ ] Collect all route descriptions
- [ ] Generate OpenAPI 3.0 YAML/JSON
- [ ] Include schemas, parameters, responses
- [ ] Auto-generate from handler signatures

### 3. Endpoints
- [ ] `GET /openapi.json` — raw spec
- [ ] `GET /openapi.yaml` — raw spec
- [ ] `GET /docs` — Swagger UI
- [ ] `GET /redoc` — ReDoc UI

### 4. Validation
- [ ] Validate requests against spec
- [ ] Validate responses against spec
- [ ] Warn on undocumented routes

### 5. Config Support
```yaml
openapi:
  enabled: true
  info:
    title: My Service API
    version: 1.0.0
    description: Order management service
  docs:
    swagger_ui: true
    redoc: true
  validation:
    requests: true
    responses: false
```

## Acceptance Criteria
- OpenAPI spec is valid and parseable
- Swagger UI renders correctly
- Spec updates when routes change
- Request validation catches invalid payloads
