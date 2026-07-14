require 'spec_helper'
require 'le_pain/openapi'

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

  describe '#generate_from_router' do
    it 'generates spec from router routes' do
      router = LePain::Router.new
      router.route('GET:/users') { |req, ctx| LePain::Response.success({}) }
      router.route('POST:/users') { |req, ctx| LePain::Response.success({}) }
      router.route('GET:/users/:id') { |req, ctx| LePain::Response.success({}) }

      spec = generator.generate_from_router(router)
      expect(spec.paths['/users'][:get]).to be_a(Hash)
      expect(spec.paths['/users'][:post]).to be_a(Hash)
      expect(spec.paths['/users/:id'][:get]).to be_a(Hash)
    end

    it 'extracts path parameters' do
      router = LePain::Router.new
      router.route('GET:/users/:id') { |req, ctx| LePain::Response.success({}) }

      spec = generator.generate_from_router(router)
      params = spec.paths['/users/:id'][:get][:parameters]
      expect(params.first[:name]).to eq('id')
      expect(params.first[:required]).to be true
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
end
