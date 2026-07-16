# OpenAPI / Swagger Generation

## Status
Done — OpenAPI now supports FastAPI-like schema annotations, JSON/YAML generation, Swagger/ReDoc endpoints, request/response schema validation, and undocumented-route warnings.

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
- [x] Collect all route descriptions
- [x] Generate OpenAPI 3.0 YAML/JSON
- [x] Include schemas, parameters, responses
- [x] Auto-generate from handler schema metadata

### 3. Endpoints
- [x] `GET /openapi.json` — raw spec
- [x] `GET /openapi.yaml` — raw spec
- [x] `GET /docs` — Swagger UI
- [x] `GET /redoc` — ReDoc UI

### 4. Validation
- [x] Validate requests against spec
- [x] Validate responses against spec
- [x] Warn on undocumented routes

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
