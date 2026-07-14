# Request/Response Middleware Pipeline

## Status
Done — named middleware pipeline, ordering, conditional execution, built-ins, custom router middleware API, and config loading are implemented and tested.

## Problem
Current middleware system is basic. Need a more powerful pipeline with named middlewares, ordering, and conditional execution.

## Goal
Replace simple `router.use` with a full middleware pipeline.

## Tasks

### 1. Middleware Registry
- [x] Named middlewares
- [x] Ordering (before/after specific middlewares)
- [x] Conditional execution (by path, transport, context)

### 2. Built-in Middlewares
- [x] `RequestId` — generate if missing
- [x] `Cors` — CORS headers for HTTP
- [x] `Compression` — gzip/deflate responses
- [x] `Timeout` — request timeout
- [x] `RequestId` — inject into response headers

### 3. Custom Middleware API
```ruby
class AuthMiddleware
  def call(request, context, next_middleware)
    return Response.unauthorized unless valid?(context.auth)
    next_middleware.call(request, context)
  end
end

router.middleware :auth, AuthMiddleware, before: :handler
router.middleware :cors, CorsMiddleware, only: { transport: :http }
```

### 4. Pipeline Execution
```
Request → RequestId → Cors → RateLimit → Auth → Idempotency → Handler → Compression → Response
```

### 5. Config Support
```yaml
middleware:
  - name: request_id
  - name: cors
    options:
      allowed_origins: ['*']
  - name: rate_limit
    options:
      limit: 100
      window: 60
  - name: auth
    options:
      header: X-Api-Key
```

## Acceptance Criteria
- Middlewares execute in defined order
- Conditional middlewares skip correctly
- Built-in middlewares work out of the box
- Custom middlewares integrate seamlessly
