# Declarative Endpoint Contracts

## Status
Open — `LePain::Schema` and route metadata exist as the first step, but endpoint contracts are not yet a first-class framework concept.

## Problem
Handlers can declare request/response schemas for OpenAPI generation, but endpoint behavior is still spread across route registration, handler code, middleware config, validation, auth, idempotency, caching, and tests. This makes endpoint contracts harder to inspect, reuse, and validate as a single source of truth.

## Goal
Promote endpoints to explicit declarative contracts, similar in spirit to FastAPI route declarations, while keeping handler bodies plain Ruby.

## Tasks

### 1. Endpoint Contract Model
```ruby
class OrdersHandler < LePain::Handler
  post "/orders",
    request: CreateOrderRequest,
    response: OrderResponse,
    summary: "Create order",
    tags: ["orders"],
    auth: :required,
    idempotency: true,
    rate_limit: { limit: 100, window: 60 },
    cache: { tags: ["orders"] }

  handle "POST:/orders" do |req, ctx|
    # plain Ruby business logic
  end
end
```

- [ ] Introduce `LePain::Endpoint` / `LePain::EndpointContract`
- [ ] Store method, path, schemas, docs, auth, cache, rate limit, idempotency, and middleware metadata together
- [ ] Expose contracts through router introspection
- [ ] Keep old `handle` and `describe` APIs backward-compatible

### 2. Typed Params, Query, Headers
```ruby
get "/orders/:id",
  params: OrderPathParams,
  query: ListOrdersQuery,
  headers: RequestHeaders,
  response: OrderResponse
```

- [ ] Support path params schema
- [ ] Support query params schema
- [ ] Support header schema
- [ ] Validate all contract sections before handler execution

### 3. Policy Declarations
- [ ] Declare auth requirements per endpoint
- [ ] Declare permissions/scopes per endpoint
- [ ] Declare idempotency strategy per endpoint
- [ ] Declare rate limits per endpoint
- [ ] Declare cache behavior and invalidation tags per endpoint

### 4. Contract-Driven Runtime
- [ ] Compile endpoint contracts into middleware/validation pipeline
- [ ] Produce consistent validation error responses for request/query/header/path params
- [ ] Optionally validate response bodies in development/test
- [ ] Surface contract metadata in logs and metrics

### 5. Contract-Driven Tooling
- [ ] Generate OpenAPI from endpoint contracts
- [ ] Generate test helpers from schemas/contracts
- [ ] Generate client stubs from contracts
- [ ] Add contract linting for undocumented routes, missing schemas, and inconsistent response codes

### 6. Developer Experience
- [ ] Clear DSL errors for invalid contract declarations
- [ ] Minimal magic: handler body remains normal Ruby
- [ ] Examples for CRUD, async submit, auth-protected endpoint, cached endpoint

## Acceptance Criteria
- Endpoint contract is the single source of truth for docs, validation, and endpoint-level policies
- OpenAPI generation uses contracts without duplicate manual metadata
- Request/path/query/header validation works from declared schemas
- Auth/idempotency/rate/cache declarations are applied consistently
- Existing handler APIs continue to work
