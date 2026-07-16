require 'spec_helper'
require 'le_pain/openapi'
require 'le_pain/schema'

RSpec.describe LePain::OpenApi::Spec do
  let(:spec) { described_class.new }

  describe '#to_h' do
    it 'returns valid OpenAPI structure' do
      hash = spec.to_h
      expect(hash[:openapi]).to eq('3.0.3')
      expect(hash[:info]).to be_a(Hash)
      expect(hash[:paths]).to be_a(Hash)
      expect(hash[:components]).to be_a(Hash)
    end
  end

  describe '#add_path' do
    it 'adds path to spec' do
      spec.add_path('get', '/users', { summary: 'List users' })
      expect(spec.paths['/users'][:get][:summary]).to eq('List users')
    end
  end

  describe '#add_schema' do
    it 'adds schema to components' do
      spec.add_schema('User', { type: 'object', properties: { id: { type: 'string' } } })
      expect(spec.components[:schemas]['User']).to be_a(Hash)
    end
  end

  describe '#to_json' do
    it 'returns valid JSON' do
      json = spec.to_json
      parsed = JSON.parse(json)
      expect(parsed['openapi']).to eq('3.0.3')
    end
  end

  describe '#to_yaml' do
    it 'returns valid YAML' do
      parsed = YAML.safe_load(spec.to_yaml)
      expect(parsed['openapi']).to eq('3.0.3')
    end
  end
end

RSpec.describe LePain::Schema do
  let(:schema_class) do
    Class.new(described_class) do
      def self.name = 'CreateOrderRequest'

      field :user_id, String, required: true
      field :items, Array, required: true, items: String
      field :priority, Integer, required: false
    end
  end

  it 'validates payloads' do
    expect(schema_class.validate('user_id' => 'u1', 'items' => ['i1'])).to be_empty

    errors = schema_class.validate('items' => [1])
    expect(errors.map(&:field)).to include('user_id', 'items.0')
  end

  it 'generates OpenAPI schema' do
    schema = schema_class.to_openapi_schema
    expect(schema[:properties]['user_id']).to eq(type: 'string')
    expect(schema[:properties]['items'][:items]).to eq(type: 'string')
    expect(schema[:required]).to eq(%w[user_id items])
  end
end

RSpec.describe LePain::OpenApi::RouteDescription do
  let(:desc) { described_class.new }

  describe '#to_operation' do
    it 'returns operation hash' do
      desc.summary = 'Create user'
      desc.tags = ['users']
      desc.add_parameter(name: 'id', in_location: 'path', required: true, schema: { type: 'string' })
      desc.add_response('201', description: 'Created')

      operation = desc.to_operation
      expect(operation[:summary]).to eq('Create user')
      expect(operation[:tags]).to eq(['users'])
      expect(operation[:parameters].size).to eq(1)
      expect(operation[:responses]['201'][:description]).to eq('Created')
    end
  end
end

RSpec.describe LePain::OpenApi::Generator do
  let(:generator) { described_class.new }
  let(:request_schema) do
    Class.new(LePain::Schema) do
      def self.name = 'CreateUserRequest'

      field :email, String, required: true, format: :email
    end
  end

  describe '#generate_from_router' do
    it 'generates spec from router routes' do
      router = LePain::Router.new
      router.route('GET:/users') { |req, ctx| LePain::Response.success({}) }
      router.route('POST:/users') { |req, ctx| LePain::Response.success({}) }
      router.route('GET:/users/:id') { |req, ctx| LePain::Response.success({}) }

      spec = generator.generate_from_router(router)
      expect(spec.paths['/users'][:get]).to be_a(Hash)
      expect(spec.paths['/users'][:post]).to be_a(Hash)
      expect(spec.paths['/users/{id}'][:get]).to be_a(Hash)
    end

    it 'extracts path parameters' do
      router = LePain::Router.new
      router.route('GET:/users/:id') { |req, ctx| LePain::Response.success({}) }

      spec = generator.generate_from_router(router)
      params = spec.paths['/users/{id}'][:get][:parameters]
      expect(params.first[:name]).to eq('id')
      expect(params.first[:required]).to be true
    end

    it 'uses handler route metadata and schemas' do
      handler_class = Class.new(LePain::Handler) do
        extend LePain::OpenApi::HandlerDsl
      end
      handler_class.post '/users', summary: 'Create user', tags: ['users'], request: request_schema
      handler_class.handle 'POST:/users' do |_req, _ctx|
        LePain::Response.success({})
      end

      router = LePain::Router.new
      router.register('POST:/users', handler_class)
      spec = generator.generate_from_router(router)

      operation = spec.paths['/users'][:post]
      expect(operation[:summary]).to eq('Create user')
      expect(operation[:requestBody][:content]['application/json'][:schema]).to eq('$ref': '#/components/schemas/CreateUserRequest')
      expect(spec.components[:schemas]['CreateUserRequest']).to be_a(Hash)
    end

    it 'records warnings for undocumented routes' do
      router = LePain::Router.new
      router.route('GET:/undocumented') { |_req, _ctx| LePain::Response.success({}) }

      generator.generate_from_router(router)

      expect(generator.warnings).to include('Route GET:/undocumented is undocumented')
    end
  end
end

RSpec.describe LePain::OpenApi::HandlerDsl do
  let(:handler_class) do
    Class.new(LePain::Handler) do
      extend LePain::OpenApi::HandlerDsl

      describe 'POST:/users' do
        self.summary = 'Create user'
        self.tags = ['users']
        add_response('201', description: 'Created')
      end

      handle 'POST:/users' do |req, ctx|
        LePain::Response.success({})
      end
    end
  end

  it 'stores route descriptions' do
    expect(handler_class.api_descriptions['POST:/users']).to be_a(LePain::OpenApi::RouteDescription)
  end

  it 'supports fastapi-style route annotations' do
    request_schema = Class.new(LePain::Schema) do
      def self.name = 'CreateOrderRequest'

      field :user_id, String
    end

    handler_class = Class.new(LePain::Handler) do
      extend LePain::OpenApi::HandlerDsl
    end
    handler_class.post '/orders', summary: 'Create order', request: request_schema

    expect(handler_class.route_metadata['POST:/orders'][:request]).to eq(request_schema)
    expect(handler_class.api_descriptions['POST:/orders'].to_operation[:summary]).to eq('Create order')
  end
end

RSpec.describe LePain::OpenApi::Handler do
  let(:router) do
    LePain::Router.new.tap do |r|
      r.route('GET:/orders') { |_req, _ctx| LePain::Response.success([]) }
    end
  end
  let(:handler) { described_class.new(router: router, config: { 'info' => { 'title' => 'Spec API' } }) }
  let(:context) { LePain::Context.new }
  let(:next_handler) { ->(_req, _ctx) { LePain::Response.not_found } }

  it 'serves openapi json' do
    response = handler.call(LePain::Request.new(action: 'GET:/openapi.json'), context, next_handler)
    expect(response.headers['Content-Type']).to eq('application/json')
    expect(response.body[:info][:title]).to eq('Spec API')
  end

  it 'serves openapi yaml' do
    response = handler.call(LePain::Request.new(action: 'GET:/openapi.yaml'), context, next_handler)
    expect(response.headers['Content-Type']).to eq('application/yaml')
    expect(response.body).to include('openapi:')
  end

  it 'serves docs html' do
    response = handler.call(LePain::Request.new(action: 'GET:/docs'), context, next_handler)
    expect(response.headers['Content-Type']).to eq('text/html')
    expect(response.body).to include('SwaggerUIBundle')
  end
end

RSpec.describe 'schema validation integration' do
  let(:schema_class) do
    Class.new(LePain::Schema) do
      def self.name = 'CreateOrderRequest'

      field :user_id, String
    end
  end

  it 'validates handler requests from route schemas' do
    handler_class = Class.new(LePain::Handler) do
      extend LePain::OpenApi::HandlerDsl
    end
    handler_class.post '/orders', request: schema_class
    handler_class.handle 'POST:/orders' do |_req, _ctx|
      LePain::Response.success({})
    end

    response = handler_class.call(LePain::Request.new(action: 'POST:/orders', payload: {}), context: LePain::Context.new)

    expect(response.status).to eq(400)
    expect(response.error[:code]).to eq('validation_error')
  end
end
