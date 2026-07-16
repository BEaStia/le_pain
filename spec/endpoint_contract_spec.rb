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

    response = router.dispatch(request)

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

    response = router.dispatch(request)

    expect(response.status).to eq(400)
    fields = response.validation_errors.map { |error| error[:field] }
    expect(fields).to include('status', 'x-client-id')
  end
end
