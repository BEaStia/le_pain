# CLI Generator

## Status
Partial — CLI scaffolding and component generation exist; runtime flags, auto-registration, and custom template directory support remain open.

## Problem
Creating a new LePain microservice requires manual setup: directory structure, config, Gemfile, handlers, etc.

## Goal
Add `lepain` CLI to scaffold new services and manage existing ones.

## Tasks

### 1. CLI Entry Point
- [ ] Create `exe/lepain` executable
- [ ] Add to gemspec executables
- [ ] Commands: `new`, `generate`, `run`

### 2. `lepain new <name>`
```
my-service/
├── Gemfile
├── config/
│   ├── le_pain.yml
│   ├── initializers/
│   └── post_initializers/
├── handlers/
│   └── example_handler.rb
├── jobs/
│   └── example_job.rb
├── services/
│   └── example_service.rb
├── Dockerfile
└── bin/
    └── start_service.sh
```

### 3. `lepain generate handler <name>`
- [ ] Generate handler file with boilerplate
- [ ] Auto-register in config

### 4. `lepain generate job <name>`
- [ ] Generate job file with boilerplate
- [ ] Auto-register in config

### 5. `lepain run`
- [ ] Start service with proper env vars
- [ ] Support `--http-port`, `--async`, `--mq` flags

### 6. Templates
- [ ] Use ERB templates for generation
- [ ] Support custom template directory

## Acceptance Criteria
- `lepain new my-service` creates working project
- Generated handlers have proper structure
- `lepain run` starts the service
- All commands have `--help` output
