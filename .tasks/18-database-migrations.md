# Database Migration System

## Status
Partial — migration base class and runner exist; SQL migration support, CLI commands, generator, and richer rollback/status workflow remain open.

## Problem
Microservices need database schema management. No built-in migration system forces users to add external tools.

## Goal
Add lightweight migration system integrated with LePain.

## Tasks

### 1. Migration Runner
- [ ] Create `LePain::Migrations::Runner`
- [ ] SQL and Ruby migration support
- [ ] Version tracking table
- [ ] Rollback support

### 2. Migration DSL
```ruby
LePain::Migration.new('20240101_create_orders') do
  up do
    execute <<-SQL
      CREATE TABLE orders (
        id UUID PRIMARY KEY,
        user_id VARCHAR NOT NULL,
        status VARCHAR DEFAULT 'pending',
        created_at TIMESTAMPTZ DEFAULT NOW()
      );
    SQL
  end

  down do
    execute 'DROP TABLE orders;'
  end
end
```

### 3. CLI Commands
- [ ] `lepain db:migrate`
- [ ] `lepain db:rollback`
- [ ] `lepain db:status`
- [ ] `lepain db:generate <name>`

### 4. Config Support
```yaml
database:
  url: postgres://user:pass@localhost/mydb
  migrations_dir: ./db/migrations
  auto_migrate: false  # run on startup
```

## Acceptance Criteria
- Migrations run in order
- Rollback works correctly
- Migration status is trackable
- CLI commands work
