require 'spec_helper'

RSpec.describe LePain::Validation::Rule do
  describe 'type validation' do
    it 'validates String type' do
      rule = described_class.new('name', type: String)
      expect(rule.validate('test')).to be_empty
      expect(rule.validate(123).first.message).to include('String')
    end

    it 'validates Integer type' do
      rule = described_class.new('count', type: Integer)
      expect(rule.validate(5)).to be_empty
      expect(rule.validate('five').first.message).to include('Integer')
    end

    it 'validates Array type' do
      rule = described_class.new('items', type: Array)
      expect(rule.validate(['a', 'b'])).to be_empty
      expect(rule.validate('not array').first.message).to include('Array')
    end

    it 'validates Hash type' do
      rule = described_class.new('data', type: Hash)
      expect(rule.validate({ key: 'val' })).to be_empty
      expect(rule.validate('not hash').first.message).to include('Hash')
    end

    it 'validates boolean type' do
      rule = described_class.new('flag', type: :boolean)
      expect(rule.validate(true)).to be_empty
      expect(rule.validate(false)).to be_empty
      expect(rule.validate('yes').first.message).to include('boolean')
    end
  end

  describe 'required validation' do
    it 'fails when required field is nil' do
      rule = described_class.new('name', required: true)
      errors = rule.validate(nil)
      expect(errors.first.message).to eq('is required')
    end

    it 'passes when optional field is nil' do
      rule = described_class.new('name', required: false)
      expect(rule.validate(nil)).to be_empty
    end
  end

  describe 'format validation' do
    it 'validates regex format' do
      rule = described_class.new('code', format: /\A[A-Z]{3}\z/)
      expect(rule.validate('ABC')).to be_empty
      expect(rule.validate('abc').first.message).to include('format')
    end

    it 'validates built-in email format' do
      rule = described_class.new('email', format: :email)
      expect(rule.validate('user@example.com')).to be_empty
      expect(rule.validate('not-email').first.message).to include('email')
    end

    it 'validates built-in url format' do
      rule = described_class.new('callback_url', format: :url)
      expect(rule.validate('https://example.com/hook')).to be_empty
      expect(rule.validate('ftp://example.com').first.message).to include('url')
    end

    it 'validates built-in uuid format' do
      rule = described_class.new('id', format: :uuid)
      expect(rule.validate('123e4567-e89b-12d3-a456-426614174000')).to be_empty
      expect(rule.validate('abc').first.message).to include('uuid')
    end
  end

  describe 'range validation' do
    it 'validates numeric range' do
      rule = described_class.new('age', min: 0, max: 120)
      expect(rule.validate(25)).to be_empty
      expect(rule.validate(-1).first.message).to include('range')
      expect(rule.validate(150).first.message).to include('range')
    end
  end

  describe 'length validation' do
    it 'validates string length' do
      rule = described_class.new('name', min_length: 2, max_length: 10)
      expect(rule.validate('John')).to be_empty
      expect(rule.validate('J').first.message).to include('length')
      expect(rule.validate('VeryLongName').first.message).to include('length')
    end

    it 'validates array length' do
      rule = described_class.new('items', min_length: 1)
      expect(rule.validate(['a'])).to be_empty
      expect(rule.validate([]).first.message).to include('length')
    end
  end

  describe 'enum validation' do
    it 'validates against allowed values' do
      rule = described_class.new('status', enum: %w[pending active done])
      expect(rule.validate('active')).to be_empty
      expect(rule.validate('unknown').first.message).to include('one of')
    end
  end

  describe 'custom validation' do
    it 'runs custom validator' do
      rule = described_class.new('code', custom: ->(v) { v.start_with?('ORD-') })
      expect(rule.validate('ORD-123')).to be_empty
      expect(rule.validate('INV-456').first.message).to include('custom')
    end
  end
end

RSpec.describe LePain::Validation::Validator do
  let(:validator) do
    described_class.new.tap do |v|
      v.required :user_id, type: String
      v.required :items, type: Array, min_length: 1
      v.optional :coupon, type: String, format: /\A[A-Z0-9]+\z/
      v.optional :quantity, type: Integer, min: 1, max: 100
    end
  end

  describe '#validate' do
    it 'returns empty array for valid payload' do
      payload = { 'user_id' => 'u1', 'items' => ['a', 'b'] }
      expect(validator.validate(payload)).to be_empty
    end

    it 'returns errors for invalid payload' do
      payload = { 'user_id' => 123, 'items' => [] }
      errors = validator.validate(payload)
      expect(errors.size).to eq(2)
      expect(errors.map(&:field)).to include('user_id', 'items')
    end

    it 'validates optional fields when present' do
      payload = { 'user_id' => 'u1', 'items' => ['a'], 'coupon' => 'invalid!' }
      errors = validator.validate(payload)
      expect(errors.size).to eq(1)
      expect(errors.first.field).to eq('coupon')
    end

    it 'validates nested objects with dotted error fields' do
      validator = described_class.new.tap do |v|
        v.required :user do
          required :email, format: :email
          required :profile do
            required :age, type: Integer, min: 18
          end
        end
      end

      errors = validator.validate({
        'user' => {
          'email' => 'invalid',
          'profile' => { 'age' => 12 },
        },
      })

      expect(errors.map(&:field)).to contain_exactly('user.email', 'user.profile.age')
    end
  end

  describe '#validate!' do
    it 'returns true for valid payload' do
      payload = { 'user_id' => 'u1', 'items' => ['a'] }
      expect(validator.validate!(payload)).to be true
    end

    it 'raises ValidationError for invalid payload' do
      payload = { 'user_id' => nil, 'items' => [] }
      expect { validator.validate!(payload) }.to raise_error(LePain::Validation::ValidationError)
    end
  end
end

RSpec.describe 'Handler validation integration' do
  let(:handler_class) do
    Class.new(LePain::Handler) do
      validate 'POST:/orders' do
        required :user_id, type: String
        required :items, type: Array, min_length: 1
      end

      handle 'POST:/orders' do |req, ctx|
        LePain::Response.success({ created: true })
      end
    end
  end

  it 'returns 400 for invalid payload' do
    req = LePain::Request.new(action: 'POST:/orders', payload: { 'user_id' => 123, 'items' => [] })
    ctx = LePain::Context.new
    resp = handler_class.call(req, context: ctx)

    expect(resp.status).to eq(400)
    expect(resp.error[:code]).to eq('validation_error')
    expect(resp.error[:details]).to eq(resp.validation_errors)
    expect(resp.validation_errors).not_to be_nil
  end

  it 'passes valid payload to handler' do
    req = LePain::Request.new(action: 'POST:/orders', payload: { 'user_id' => 'u1', 'items' => ['a'] })
    ctx = LePain::Context.new
    resp = handler_class.call(req, context: ctx)

    expect(resp.status).to eq(200)
    expect(resp.body).to eq({ created: true })
  end

  it 'runs validation before before_filter and skips handler execution' do
    execution = []
    handler = Class.new(LePain::Handler) do
      validate 'POST:/orders' do
        required :user_id, type: String
      end

      before_filter do |_req, _ctx|
        execution << :before_filter
        nil
      end

      handle 'POST:/orders' do |_req, _ctx|
        execution << :handler
        LePain::Response.success({})
      end
    end

    req = LePain::Request.new(action: 'POST:/orders', payload: { 'user_id' => 123 })
    resp = handler.call(req, context: LePain::Context.new)

    expect(resp.status).to eq(400)
    expect(execution).to be_empty
  end
end
