# WebSocket Transport

## Status
Open — no WebSocket adapter, connection manager, push/broadcast API, or heartbeat/session recovery implementation found.

## Problem
Some use cases need real-time bidirectional communication (notifications, live updates, chat). Current transports are request-response only.

## Goal
Add WebSocket transport with the same unified handler pattern.

## Tasks

### 1. WebSocket Server
- [ ] Create `LePain::Transports::WebSocketAdapter`
- [ ] Connection management (connect, disconnect, reconnect)
- [ ] Message framing (JSON over WebSocket)

### 2. Unified Handler Pattern
```ruby
class NotificationHandler < LePain::Handler
  handle 'ws:connect' do |request, context|
    # client connected
  end

  handle 'ws:disconnect' do |request, context|
    # client disconnected
  end

  handle 'ws:message' do |request, context|
    # message received
    LePain::Response.success({ ack: true })
  end
end
```

### 3. Server Push
- [ ] `LePain::WebSocket.push(client_id, message)`
- [ ] Broadcast to all connected clients
- [ ] Broadcast to topic subscribers

### 4. Connection State
- [ ] Track connected clients
- [ ] Heartbeat/ping-pong
- [ ] Auto-reconnect with session recovery

### 5. Config Support
```yaml
websocket:
  enabled: true
  port: 3003
  heartbeat_interval: 30
  max_connections: 1000
  allowed_origins: ['https://myapp.com']
```

## Acceptance Criteria
- WebSocket connections work alongside HTTP
- Messages are routed to correct handlers
- Server can push messages to clients
- Heartbeat detects dead connections
