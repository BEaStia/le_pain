# Plugin System

## Status
Partial — plugin base, registry, load order, and lifecycle hooks exist; dependency resolution and official plugin packages remain open.

## Problem
Adding new features requires modifying core code. Users can't easily extend the framework.

## Goal
Add a plugin system for community extensions and custom integrations.

## Tasks

### 1. Plugin Interface
```ruby
class MyPlugin < LePain::Plugin
  def name; 'my-plugin'; end
  def version; '1.0.0'; end

  def configure(app, config)
    # modify app, register middleware, etc
  end

  def start(app)
    # start background workers, connections
  end

  def stop(app)
    # cleanup
  end
end
```

### 2. Plugin Registry
- [ ] `LePain::Plugins.register(MyPlugin.new)`
- [ ] Load order matters
- [ ] Dependency resolution between plugins

### 3. Lifecycle Hooks
- [ ] `before_initialize`
- [ ] `after_initialize`
- [ ] `before_start`
- [ ] `after_start`
- [ ] `before_stop`

### 4. Plugin Config
```yaml
plugins:
  - name: le_pain-prometheus
    options:
      port: 3002
  - name: le_pain-sentry
    options:
      dsn: https://...
  - name: ./plugins/my_custom_plugin.rb
    options:
      custom_option: value
```

### 5. Official Plugins
- [ ] `le_pain-prometheus` — metrics
- [ ] `le_pain-sentry` — error tracking
- [ ] `le_pain-redis` — Redis integration
- [ ] `le_pain-postgres` — PostgreSQL integration

## Acceptance Criteria
- Plugins can register middleware, routes, handlers
- Plugins have access to app lifecycle
- Plugin config is passed correctly
- Plugin errors don't crash the app
