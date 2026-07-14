# Schema Registry

## Status
Open — no schema registry, schema validation, schema versioning, compatibility checks, or registry provider implementation found.

## Problem
Message schemas evolve across services. No central place to manage and validate message contracts.

## Goal
Add schema registry for message validation and versioning.

## Tasks

### 1. Schema Definition
```ruby
LePain::SchemaRegistry.register(
  'order.created.v1',
  type: :json_schema,
  schema: {
    type: 'object',
    required: ['user_id', 'items'],
    properties: {
      user_id: { type: 'string' },
      items: { type: 'array', items: { type: 'string' } },
    },
  },
)
```

### 2. Validation
- [ ] Validate incoming messages against schema
- [ ] Validate outgoing messages against schema
- [ ] Return clear validation errors

### 3. Versioning
- [ ] Schema versioning (v1, v2, v3)
- [ ] Backward compatibility checks
- [ ] Deprecation warnings for old versions

### 4. Storage
- [ ] In-memory registry
- [ ] File-based registry
- [ ] Remote registry (Confluent Schema Registry compatible)

### 5. Config Support
```yaml
schema_registry:
  type: remote
  url: http://schema-registry:8081
  validation:
    incoming: true
    outgoing: false
```

## Acceptance Criteria
- Messages are validated against schemas
- Schema versions are managed
- Compatibility checks work
- Remote registry integration works
