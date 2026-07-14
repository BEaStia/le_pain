require 'spec_helper'

RSpec.describe LePain::Response do
  describe '.success' do
    it 'creates a successful response' do
      resp = described_class.success({ id: 1 }, status: 201)
      expect(resp.success?).to be true
      expect(resp.status).to eq(201)
      expect(resp.body).to eq({ id: 1 })
    end
  end

  describe '.error' do
    it 'creates an error response' do
      resp = described_class.error('not found', status: 404, code: 'not_found')
      expect(resp.success?).to be false
      expect(resp.status).to eq(404)
      expect(resp.error[:message]).to eq('not found')
      expect(resp.error[:code]).to eq('not_found')
    end
  end

  describe '.not_found' do
    it 'creates a 404 response' do
      resp = described_class.not_found('missing')
      expect(resp.status).to eq(404)
      expect(resp.error[:code]).to eq('not_found')
    end
  end

  describe '.bad_request' do
    it 'creates a 400 response' do
      resp = described_class.bad_request('invalid')
      expect(resp.status).to eq(400)
    end
  end

  describe '.unauthorized' do
    it 'creates a 401 response' do
      resp = described_class.unauthorized
      expect(resp.status).to eq(401)
    end
  end

  describe '#to_json' do
    it 'serializes to JSON' do
      resp = described_class.success({ id: 1 })
      json = resp.to_json
      expect(json).to include('"status":200')
      expect(json).to include('"id":1')
    end
  end
end
