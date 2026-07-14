# Service Discovery Integration

## Status
Open — no service discovery registry, provider integrations, health filtering, or load-balancing implementation found.

## Problem
Microservices need to find each other. Hardcoding URLs doesn't scale in dynamic environments (Kubernetes, cloud).

## Goal
Add service discovery support for dynamic service location.

## Tasks

### 1. Discovery Interface
```ruby
LePain::Discovery.register(:consul, url: 'http://consul:8500')
LePain::Discovery.register(:k8s, namespace: 'default')
LePain::Discovery.register(:dns, domain: 'svc.cluster.local')
```

### 2. Built-in Providers
- [ ] **Consul** — HTTP API integration
- [ ] **Kubernetes** — DNS and API
- [ ] **DNS** — SRV record resolution
- [ ] **Eureka** — Netflix service discovery
- [ ] **Static** — manual config for dev

### 3. HTTP Client Integration
```ruby
# Instead of hardcoded URL
client = LePain::HttpClient.new(service: 'order-service')
client.post('/orders', body: {...})

# Resolves to actual URL via discovery
```

### 4. Health-Aware Routing
- [ ] Skip unhealthy instances
- [ ] Load balancing (round-robin, random, least-connections)
- [ ] Retry on different instances

### 5. Config Support
```yaml
discovery:
  provider: consul
  url: http://consul:8500
  services:
    order-service:
      health_check: true
      load_balancer: round_robin
    payment-service:
      health_check: true
      load_balancer: least_connections
```

## Acceptance Criteria
- Services are resolved dynamically
- Unhealthy instances are skipped
- Load balancing works correctly
- Fallback to static config when discovery fails
