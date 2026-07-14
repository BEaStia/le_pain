# gRPC Transport

## Status
Open — no gRPC adapter, proto generation, Ruby stubs, or streaming support implementation found.

## Problem
Some systems use gRPC for high-performance internal communication. Current framework only supports HTTP and MQ.

## Goal
Add gRPC transport with the same unified handler pattern.

## Tasks

### 1. gRPC Server
- [ ] Create `LePain::Transports::GrpcAdapter`
- [ ] Proto file auto-generation from handlers
- [ ] Bidirectional streaming support

### 2. Unified Handler Pattern
```ruby
class OrderHandler < LePain::Handler
  handle 'grpc:OrderService/CreateOrder' do |request, context|
    order = OrderService.create(...)
    LePain::Response.success(order)
  end

  handle 'grpc:OrderService/StreamOrders' do |request, context|
    # streaming response
  end
end
```

### 3. Proto Generation
- [ ] Auto-generate `.proto` files from registered handlers
- [ ] Generate Ruby client stubs
- [ ] Generate documentation

### 4. Streaming
- [ ] Server streaming
- [ ] Client streaming
- [ ] Bidirectional streaming

### 5. Config Support
```yaml
grpc:
  enabled: true
  port: 50051
  proto_dir: ./protos
  services:
    - OrderService
    - UserService
```

## Acceptance Criteria
- gRPC server starts and accepts connections
- Handlers are mapped to gRPC methods
- Proto files are generated correctly
- Streaming works for all types
