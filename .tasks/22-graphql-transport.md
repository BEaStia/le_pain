# GraphQL Transport

## Status
Open — no GraphQL adapter, schema DSL, query engine, subscriptions, or federation/introspection implementation found.

## Problem
Some clients prefer GraphQL over REST for flexible data fetching. Current framework is REST/MQ focused.

## Goal
Add GraphQL transport with the same unified handler pattern.

## Tasks

### 1. GraphQL Server
- [ ] Create `LePain::Transports::GraphqlAdapter`
- [ ] Schema definition DSL
- [ ] Query execution engine
- [ ] Subscription support (via WebSocket)

### 2. Unified Handler Pattern
```ruby
class OrderGraphql < LePain::GraphqlSchema
  type :Order do
    field :id, ID
    field :user_id, String
    field :status, String
    field :items, [String]
  end

  query do
    field :order, Order do
      argument :id, ID
      resolve ->(obj, args, ctx) { OrderService.get(args[:id]) }
    end
  end

  mutation do
    field :createOrder, Order do
      argument :user_id, String
      argument :items, [String]
      resolve ->(obj, args, ctx) { OrderService.create(args) }
    end
  end
end
```

### 3. Integration
- [ ] Route `POST:/graphql` for queries
- [ ] Route `ws:/graphql` for subscriptions
- [ ] Introspection endpoint
- [ ] Apollo Federation support

### 4. Config Support
```yaml
graphql:
  enabled: true
  path: /graphql
  introspection: true
  max_depth: 10
  max_complexity: 100
```

## Acceptance Criteria
- GraphQL queries execute correctly
- Mutations work as expected
- Subscriptions push real-time updates
- Introspection returns valid schema
