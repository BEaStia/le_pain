# Distributed Tracing Export

## Status
Partial — custom spans, tracer, console exporter, and OTLP-style exporter exist; OpenTelemetry dependency, W3C trace context, and auto-instrumentation remain open.

## Problem
Trace IDs are tracked internally but not exported to external tracing systems (Jaeger, Zipkin, OpenTelemetry).

## Goal
Export trace spans to OpenTelemetry-compatible backends.

## Tasks

### 1. OpenTelemetry Integration
- [ ] Add `opentelemetry-sdk` as optional dependency
- [ ] Create `LePain::Tracing::OpenTelemetryExporter`
- [ ] Auto-instrument: HTTP requests, MQ messages, job execution

### 2. Span Creation
- [ ] Span per request/message
- [ ] Parent-child relationships (trace_id propagation)
- [ ] Attributes: transport, action, status, duration, error
- [ ] Events: handler started, handler completed, error

### 3. Context Propagation
- [ ] W3C Trace Context headers (`traceparent`, `tracestate`)
- [ ] Extract from incoming requests
- [ ] Inject into outgoing requests

### 4. Config Support
```yaml
tracing:
  enabled: true
  exporter: otlp  # otlp, jaeger, zipkin, console
  endpoint: http://otel-collector:4318
  service_name: my-service
  sample_rate: 1.0  # 100% sampling
```

### 5. Console Exporter (dev)
- [ ] Print spans to stdout in dev mode
- [ ] Include: trace_id, span_id, parent_id, name, duration, status

## Acceptance Criteria
- Spans are exported to OTLP endpoint
- Trace context propagates across services
- Console exporter works in dev mode
- Sampling rate is configurable
