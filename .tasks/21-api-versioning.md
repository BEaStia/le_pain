# API Versioning

## Status
Open — no API version router/middleware, version negotiation, deprecation headers, or compatibility fallback implementation found.

## Problem
APIs evolve. Breaking changes need versioning without breaking existing clients.

## Goal
Add API versioning support with backward compatibility.

## Tasks

### 1. Version Strategies
- [ ] **URL path**: `/v1/orders`, `/v2/orders`
- [ ] **Header**: `Accept: application/vnd.myapi.v1+json`
- [ ] **Query param**: `/orders?api_version=1`

### 2. Version-Aware Routing
```ruby
router.versioned do
  version :v1 do
    route 'POST:/orders' do |req, ctx|
      # v1 logic
    end
  end

  version :v2 do
    route 'POST:/orders' do |req, ctx|
      # v2 logic with new fields
    end
  end
end
```

### 3. Deprecation Support
- [ ] `Deprecation` header on responses
- [ ] `Sunset` header for removal date
- [ ] Warning logs for deprecated endpoint usage
- [ ] Configurable deprecation period

### 4. Version Negotiation
- [ ] Client specifies preferred version
- [ ] Server responds with actual version used
- [ ] Fallback to latest compatible version

### 5. Config Support
```yaml
api:
  versioning:
    strategy: url_path  # url_path, header, query_param
    default_version: v1
    latest_version: v2
    deprecation:
      warning_header: true
      sunset_days: 90
```

## Acceptance Criteria
- Multiple API versions coexist
- Deprecation headers are present
- Version negotiation works
- Old versions can be retired gracefully
