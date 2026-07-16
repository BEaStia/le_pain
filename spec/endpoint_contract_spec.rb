require 'spec_helper'
require 'le_pain/endpoint_contract'

RSpec.describe LePain::EndpointContract do
  let(:request_schema) do
    Class.new(LePain::Schema) do
      def self.name = 'CreateOrderRequest'

      field :user_id, String
    end
  end

  it 'stores endpoint metadata as a first-class contract' do
    contract = described_class.new(
      method: :post,
      path: 'orders',
      request: request_schema,
      auth: :required,
      idempotency: true,
      rate_limit: { limit: 100, window: 60 },
      cache: { tags: ['orders'] },
      summary: 'Create order'
    )

    expect(contract.action).to eq('POST:/orders')
    expect(contract.request_schema).to eq(request_schema)
    expect(contract.policies).to include(auth: :required, idempotency: true)
    expect(contract.docs).to include(summary: 'Create order')
    expect(contract.to_h[:schemas]).to include(request: 'CreateOrderRequest')
  end

  it 'rejects invalid schema declarations' do
    expect do
      described_class.new(method: :post, path: '/orders', request: Object.new)
    end.to raise_error(ArgumentError, /request must be/)
  end
end

RSpec.describe 'endpoint contract integration' do
  let(:path_schema) do
    Class.new(LePain::Schema) do
      def self.name = 'OrderPathParams'

      field :id, String
    end
  end

  let(:query_schema) do
    Class.new(LePain::Schema) do
      def self.name = 'OrderQuery'

      field :include_items, String, required: false
    end
  end

  let(:header_schema) do
    Class.new(LePain::Schema) do
      def self.name = 'OrderHeaders'

      field :'x-client-id', String
    end
  end

  let(:body_schema) do
    Class.new(LePain::Schema) do
      def self.name = 'UpdateOrderRequest'

      field :status, String
    end
  end

  let(:handler_class) do
    path = path_schema
    query = query_schema
    headers = header_schema
    body = body_schema

    Class.new(LePain::Handler) do
      post '/orders/:id',
           params: path,
           query: query,
           headers: headers,
           request: body,
           auth: :required,
           rate_limit: { limit: 10, window: 60 },
           summary: 'Update order'

      handle 'POST:/orders/:id' do |req, _ctx|
        LePain::Response.success({ id: req['id'], status: req['status'] })
      end
    end
  end

  it 'exposes endpoint contracts through the handler and router' do
    router = LePain::Router.new
    router.register('POST:/orders/:id', handler_class)

    contract = handler_class.endpoint_contracts['POST:/orders/:id']
    expect(contract).to be_a(LePain::EndpointContract)
    expect(router.endpoint_contracts['POST:/orders/:id']).to eq(contract)
  end

  it 'validates path params, query, headers, and request body from contracts' do
    router = LePain::Router.new
    router.register('POST:/orders/:id', handler_class)
    request = LePain::Request.from_http(
      method: 'POST',
      path: '/orders/o-1',
      body: { status: 'paid' },
      query: { include_items: 'true' },
      headers: { 'x-client-id' => 'client-1' }
    )

    response = router.dispatch(request, context: LePain::Context.new(auth: 'token'))

    expect(response).to be_success
    expect(response.body).to include(id: 'o-1', status: 'paid')
  end

  it 'returns validation errors when any contract section is invalid' do
    router = LePain::Router.new
    router.register('POST:/orders/:id', handler_class)
    request = LePain::Request.from_http(
      method: 'POST',
      path: '/orders/o-1',
      body: {},
      headers: {}
    )

    response = router.dispatch(request, context: LePain::Context.new(auth: 'token'))

    expect(response.status).to eq(400)
    fields = response.validation_errors.map { |error| error[:field] }
    expect(fields).to include('status', 'x-client-id')
  end

  it 'enforces auth and permissions policies' do
    secured_handler = Class.new(LePain::Handler) do
      get '/admin', auth: :required, permissions: [:admin]

      handle 'GET:/admin' do |_req, _ctx|
        LePain::Response.success({})
      end
    end
    request = LePain::Request.from_http(method: 'GET', path: '/admin')

    unauthorized = secured_handler.call(request, context: LePain::Context.new)
    forbidden = secured_handler.call(request, context: LePain::Context.new(auth: 'token', metadata: { permissions: [] }))
    allowed = secured_handler.call(request, context: LePain::Context.new(auth: 'token', metadata: { permissions: [:admin] }))

    expect(unauthorized.status).to eq(401)
    expect(forbidden.status).to eq(403)
    expect(allowed).to be_success
  end

  it 'applies endpoint idempotency policies' do
    calls = 0
    handler = Class.new(LePain::Handler) do
      post '/orders', idempotency: true

      handle 'POST:/orders' do |_req, _ctx|
        calls = calls + 1
        LePain::Response.success({ calls: calls })
      end
    end
    request = LePain::Request.from_http(method: 'POST', path: '/orders', headers: { 'idempotency-key' => 'idem-1' })

    first = handler.call(request, context: LePain::Context.new)
    second = handler.call(request, context: LePain::Context.new)

    expect(first.body[:calls]).to eq(1)
    expect(second.body[:calls]).to eq(1)
  end

  it 'applies endpoint rate limits' do
    handler = Class.new(LePain::Handler) do
      get '/limited', rate_limit: { limit: 1, window: 60 }

      handle 'GET:/limited' do |_req, _ctx|
        LePain::Response.success({})
      end
    end
    request = LePain::Request.from_http(method: 'GET', path: '/limited')
    context = LePain::Context.new(auth: 'client-1')

    expect(handler.call(request, context: context)).to be_success
    limited = handler.call(request, context: context)

    expect(limited.status).to eq(429)
    expect(limited.headers['X-RateLimit-Remaining']).to eq('0')
  end

  it 'applies endpoint cache policies' do
    LePain::Cache.default_store = LePain::Cache::Store.new
    calls = 0
    handler = Class.new(LePain::Handler) do
      get '/cached', cache: { tags: ['cached'] }

      handle 'GET:/cached' do |_req, _ctx|
        calls = calls + 1
        LePain::Response.success({ calls: calls })
      end
    end
    request = LePain::Request.from_http(method: 'GET', path: '/cached')

    first = handler.call(request, context: LePain::Context.new)
    second = handler.call(request, context: LePain::Context.new)

    expect(first.body[:calls]).to eq(1)
    expect(second.body[:calls]).to eq(1)
  end
end

RSpec.describe LePain::EndpointContracts::Linter do
  it 'reports missing contracts and schemas' do
    contracted = Class.new(LePain::Handler) do
      get '/orders'
      handle 'GET:/orders' do |_req, _ctx|
        LePain::Response.success({})
      end
    end
    router = LePain::Router.new
    router.register('GET:/orders', contracted)
    router.route('GET:/health') { |_req, _ctx| LePain::Response.success({}) }

    warnings = described_class.lint(router)

    expect(warnings).to include('Route GET:/orders has no response schema')
    expect(warnings).to include('Route GET:/health has no endpoint contract')
  end
end

RSpec.describe LePain::EndpointContracts::TestHelpers do
  include described_class

  it 'builds requests from endpoint contracts' do
    contract = LePain::EndpointContract.new(method: :get, path: '/orders/:id')

    request = build_contract_request(contract, params: { id: 'o-1' }, query: { expand: 'items' })

    expect(request.action).to eq('GET:/orders/o-1')
    expect(request.metadata['query']).to eq('expand' => 'items')
  end
end

RSpec.describe LePain::EndpointContracts::ClientStubGenerator do
  it 'generates simple client stubs from router contracts' do
    handler = Class.new(LePain::Handler) do
      get '/orders/:id'
    end
    router = LePain::Router.new
    router.register('GET:/orders/:id', handler)

    output = described_class.generate(router, module_name: 'OrdersClient')

    expect(output).to include('module OrdersClient')
    expect(output).to include('def get_orders_by_id')
  end
end
