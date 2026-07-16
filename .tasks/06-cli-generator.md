# CLI Generator

## Status
Done — CLI scaffolding, component generation, runtime flags, auto-registration, and custom template directory support are implemented.

## Problem
Creating a new LePain microservice requires manual setup: directory structure, config, Gemfile, handlers, etc.

## Goal
Add `lepain` CLI to scaffold new services and manage existing ones.

## Tasks

### 1. CLI Entry Point
- [x] Create `exe/lepain` executable
- [x] Add to gemspec executables
- [x] Commands: `new`, `generate`, `run`

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
- [x] Generate handler file with boilerplate
- [x] Auto-register in config

### 4. `lepain generate job <name>`
- [x] Generate job file with boilerplate
- [x] Auto-register in config

### 5. `lepain run`
- [x] Start service with proper env vars
- [x] Support `--http-port`, `--async`, `--mq` flags

### 6. Templates
- [x] Use ERB templates for generation
- [x] Support custom template directory

## Acceptance Criteria
- `lepain new my-service` creates working project
- Generated handlers have proper structure
- `lepain run` starts the service
- All commands have `--help` output
