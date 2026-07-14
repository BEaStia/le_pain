# PostgreSQL Task Store

## Status
Partial — PostgreSQL task store with CRUD, filters, pooling, and cleanup exists; pagination, full-text search, and scheduled cleanup remain open.

## Problem
Memory store loses data on restart. File store doesn't scale. Redis requires separate infrastructure. PostgreSQL is often already available.

## Goal
Add PostgreSQL as a task store backend with proper schema and indexing.

## Tasks

### 1. Schema
```sql
CREATE TABLE lepain_tasks (
  id UUID PRIMARY KEY,
  type VARCHAR NOT NULL,
  state VARCHAR NOT NULL,
  payload JSONB,
  result JSONB,
  error JSONB,
  context JSONB,
  created_at TIMESTAMPTZ NOT NULL,
  updated_at TIMESTAMPTZ NOT NULL,
  started_at TIMESTAMPTZ,
  completed_at TIMESTAMPTZ,
  attempts INTEGER DEFAULT 0
);

CREATE INDEX idx_lepain_tasks_state ON lepain_tasks(state);
CREATE INDEX idx_lepain_tasks_created ON lepain_tasks(created_at DESC);
CREATE INDEX idx_lepain_tasks_type ON lepain_tasks(type);
```

### 2. Implementation
- [ ] Create `LePain::TaskStores::PostgresStore`
- [ ] Use `pg` gem (optional dependency)
- [ ] Connection pool support
- [ ] Transactional updates

### 3. Query Support
- [ ] `list(state:, type:, limit:)` with proper WHERE clauses
- [ ] Pagination support
- [ ] Full-text search on payload

### 4. Cleanup
- [ ] Background job to delete expired finished tasks
- [ ] Configurable cleanup interval

### 5. Config Support
```yaml
task_store:
  type: postgres
  options:
    connection_string: postgres://user:pass@localhost/lepain
    pool_size: 5
    ttl: 86400
```

## Acceptance Criteria
- Tasks persist across restarts
- Queries are fast with proper indexes
- Connection pool handles concurrent access
- Cleanup removes old tasks automatically
