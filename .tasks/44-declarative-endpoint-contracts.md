# Declarative Endpoint Contracts

## Status
Done — endpoint contracts are first-class, drive validation, policy runtime, OpenAPI metadata, logs/metrics, linting, test helpers, and client stub generation.

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

- [x] Introduce `LePain::Endpoint` / `LePain::EndpointContract`
- [x] Store method, path, schemas, docs, auth, cache, rate limit, idempotency, and middleware metadata together
- [x] Expose contracts through router introspection
- [x] Keep old `handle` and `describe` APIs backward-compatible

### 2. Typed Params, Query, Headers
```ruby
get "/orders/:id",
  params: OrderPathParams,
  query: ListOrdersQuery,
  headers: RequestHeaders,
  response: OrderResponse
```

- [x] Support path params schema
- [x] Support query params schema
- [x] Support header schema
- [x] Validate all contract sections before handler execution

### 3. Policy Declarations
- [x] Declare auth requirements per endpoint
- [x] Declare permissions/scopes per endpoint
- [x] Declare idempotency strategy per endpoint
- [x] Declare rate limits per endpoint
- [x] Declare cache behavior and invalidation tags per endpoint

### 4. Contract-Driven Runtime
- [x] Compile endpoint contracts into middleware/validation pipeline
- [x] Produce consistent validation error responses for request/query/header/path params
- [x] Optionally validate response bodies in development/test
- [x] Surface contract metadata in logs and metrics

### 5. Contract-Driven Tooling
- [x] Generate OpenAPI from endpoint contracts
- [x] Generate test helpers from schemas/contracts
- [x] Generate client stubs from contracts
- [x] Add contract linting for undocumented routes, missing schemas, and inconsistent response codes

### 6. Developer Experience
- [x] Clear DSL errors for invalid contract declarations
- [x] Minimal magic: handler body remains normal Ruby
- [x] Examples for CRUD, async submit, auth-protected endpoint, cached endpoint

## Acceptance Criteria
- Endpoint contract is the single source of truth for docs, validation, and endpoint-level policies
- OpenAPI generation uses contracts without duplicate manual metadata
- Request/path/query/header validation works from declared schemas
- Auth/idempotency/rate/cache declarations are applied consistently
- Existing handler APIs continue to work
