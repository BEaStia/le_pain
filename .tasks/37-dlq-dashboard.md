# Dead Letter Queue Dashboard

## Status
Open — no DLQ dashboard routes, item inspection, retry/delete/export actions, auth protection, or live updates implementation found.

## Problem
Failed jobs accumulate in DLQ but there's no visibility into why they failed or how to fix them.

## Goal
Add a web dashboard for inspecting and managing dead letter queue items.

## Tasks

### 1. Dashboard UI
- [ ] List all DLQ items with filters
- [ ] Search by task_id, type, error message
- [ ] Sort by date, type, attempts
- [ ] Pagination

### 2. Item Details
- [ ] Full task payload
- [ ] Error message and backtrace
- [ ] Execution timeline
- [ ] Retry history

### 3. Actions
- [ ] Retry single item
- [ ] Retry all items of same type
- [ ] Delete item
- [ ] Export to JSON/CSV

### 4. Integration
- [ ] Mount as route: `GET /dlq/dashboard`
- [ ] Auth protection (admin only)
- [ ] WebSocket for real-time updates

### 5. Config Support
```yaml
dlq_dashboard:
  enabled: true
  path: /dlq/dashboard
  auth:
    required: true
    admin_token: secret123
  max_items: 10000
```

## Acceptance Criteria
- Dashboard renders correctly
- Filters and search work
- Retry actions trigger job re-execution
- Auth prevents unauthorized access
