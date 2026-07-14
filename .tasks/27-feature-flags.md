# Feature Flags

## Status
Partial — boolean, percentage, user-targeted, time-based, registry, and config loading exist; variants, external providers, provider interface, and metrics remain open.

## Problem
Deploying new features requires coordination. Can't test in production or gradually roll out changes.

## Goal
Add feature flag support for gradual rollouts and A/B testing.

## Tasks

### 1. Feature Flag API
```ruby
if LePain::Features.enabled?(:new_checkout, context: ctx)
  # new logic
else
  # old logic
end
```

### 2. Flag Strategies
- [ ] Boolean on/off
- [ ] Percentage rollout
- [ ] User-targeted (by user_id, tenant, etc.)
- [ ] Time-based (enable at specific time)
- [ ] A/B test variants

### 3. Storage Backends
- [ ] Config file (static)
- [ ] Redis (dynamic)
- [ ] LaunchDarkly integration
- [ ] Custom provider interface

### 4. Evaluation Context
```yaml
features:
  new_checkout:
    enabled: true
    strategy: percentage
    percentage: 25
    seed: user_id

  dark_mode:
    enabled: true
    strategy: user_targeted
    users: ['user-1', 'user-2']

  beta_api:
    enabled: true
    strategy: time_based
    enable_at: '2024-06-01T00:00:00Z'
```

### 5. Metrics
- [ ] Flag evaluation count
- [ ] Flag enable/disable ratio
- [ ] A/B test variant distribution

## Acceptance Criteria
- Flags evaluate correctly per strategy
- Percentage rollout is consistent
- User-targeted flags work
- Dynamic flag changes apply without restart
