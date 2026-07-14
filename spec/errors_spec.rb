require 'spec_helper'
require 'le_pain/errors'

RSpec.describe LePain::Errors do
  describe 'Error Hierarchy' do
    describe LePain::Errors::ClientError::BadRequest do
      it 'has status 400' do
        error = described_class.new
        expect(error.status).to eq(400)
        expect(error.code).to eq('bad_request')
      end
    end

    describe LePain::Errors::ClientError::Unauthorized do
      it 'has status 401' do
        error = described_class.new
        expect(error.status).to eq(401)
      end
    end

    describe LePain::Errors::ClientError::Forbidden do
      it 'has status 403' do
        error = described_class.new
        expect(error.status).to eq(403)
      end
    end

    describe LePain::Errors::ClientError::NotFound do
      it 'has status 404' do
        error = described_class.new
        expect(error.status).to eq(404)
      end
    end

    describe LePain::Errors::ClientError::ValidationError do
      it 'has status 422 and includes validation errors' do
        error = described_class.new('Invalid data', validation_errors: ['field is required'])
        expect(error.status).to eq(422)
        expect(error.validation_errors).to eq(['field is required'])
      end
    end

    describe LePain::Errors::ServerError::InternalError do
      it 'has status 500' do
        error = described_class.new
        expect(error.status).to eq(500)
      end
    end

    describe LePain::Errors::ServerError::NotImplemented do
      it 'has status 501' do
        error = described_class.new
        expect(error.status).to eq(501)
      end
    end

    describe LePain::Errors::ServerError::ServiceUnavailable do
      it 'has status 503' do
        error = described_class.new
        expect(error.status).to eq(503)
      end
    end

    describe LePain::Errors::TransientError::Timeout do
      it 'is retryable' do
        error = described_class.new
        expect(error.status).to eq(504)
        expect(error.retryable?).to be true
      end
    end

    describe LePain::Errors::TransientError::ConnectionRefused do
      it 'is retryable' do
        error = described_class.new
        expect(error.status).to eq(503)
        expect(error.retryable?).to be true
      end
    end

    describe LePain::Errors::TransientError::RateLimited do
      it 'is retryable' do
        error = described_class.new
        expect(error.status).to eq(429)
        expect(error.retryable?).to be true
      end
    end

    describe LePain::Errors::PermanentError::InvalidState do
      it 'is not retryable' do
        error = described_class.new
        expect(error.status).to eq(409)
        expect(error.retryable?).to be false
      end
    end

    describe LePain::Errors::PermanentError::BusinessRuleViolation do
      it 'is not retryable' do
        error = described_class.new
        expect(error.status).to eq(422)
        expect(error.retryable?).to be false
      end
    end
  end

  describe 'Error Context' do
    it 'attaches context to errors' do
      error = LePain::Errors::Base.new(
        'Test error',
        context: { user_id: '123', action: 'create' }
      )
      expect(error.context[:user_id]).to eq('123')
      expect(error.context[:action]).to eq('create')
    end

    it 'attaches original error' do
      original = StandardError.new('Original')
      error = LePain::Errors::Base.new('Wrapped', original_error: original)
      expect(error.original_error).to eq(original)
    end
  end

  describe 'Error Response Format' do
    it 'returns structured JSON' do
      error = LePain::Errors::ClientError::BadRequest.new(
        'Invalid payload',
        context: { request_id: 'req-001', trace_id: 'trace-abc' }
      )

      json = error.to_h
      expect(json[:status]).to eq(400)
      expect(json[:error][:code]).to eq('bad_request')
      expect(json[:error][:message]).to eq('Invalid payload')
      expect(json[:error][:request_id]).to eq('req-001')
      expect(json[:error][:trace_id]).to eq('trace-abc')
    end
  end

  describe LePain::Errors::Handler do
    let(:handler) { described_class.new }

    describe '#handle' do
      it 'classifies Timeout errors as transient' do
        error = Timeout::Error.new('Connection timed out')
        classified = handler.handle(error)

        expect(classified).to be_a(LePain::Errors::TransientError::Timeout)
        expect(classified.retryable?).to be true
      end

      it 'classifies ECONNREFUSED as transient' do
        error = Errno::ECONNREFUSED.new('Connection refused')
        classified = handler.handle(error)

        expect(classified).to be_a(LePain::Errors::TransientError::ConnectionRefused)
        expect(classified.retryable?).to be true
      end

      it 'classifies ArgumentError as client error' do
        error = ArgumentError.new('Invalid argument')
        classified = handler.handle(error)

        expect(classified).to be_a(LePain::Errors::ClientError::BadRequest)
      end

      it 'classifies unknown errors as server errors' do
        error = StandardError.new('Something went wrong')
        classified = handler.handle(error)

        expect(classified).to be_a(LePain::Errors::ServerError::InternalError)
      end

      it 'enriches error with context' do
        error = StandardError.new('Test')
        classified = handler.handle(
          error,
          context: {
            request_id: 'req-123',
            trace_id: 'trace-456',
            correlation_id: 'corr-789'
          }
        )

        expect(classified.context[:request_id]).to eq('req-123')
        expect(classified.context[:trace_id]).to eq('trace-456')
        expect(classified.context[:correlation_id]).to eq('corr-789')
      end

      it 'attaches backtrace only when configured' do
        error = StandardError.new('Traceable')
        error.set_backtrace(['/tmp/app.rb:1'])

        without_backtrace = described_class.new.handle(error)
        with_backtrace = described_class.new(include_backtrace: true).handle(error)

        expect(without_backtrace.context).not_to have_key(:backtrace)
        expect(with_backtrace.context[:backtrace]).to eq(['/tmp/app.rb:1'])
      end

      it 'preserves existing LePain errors' do
        error = LePain::Errors::ClientError::NotFound.new('Resource not found')
        classified = handler.handle(error)

        expect(classified).to eq(error)
      end
    end

    describe 'automatic handling strategies' do
      it 'logs transient errors as warnings' do
        error = Timeout::Error.new
        expect(LePain::Application.logger).to receive(:warn)

        handler.handle(error)
      end

      it 'logs server errors and alerts ops' do
        alert_called = false
        handler = described_class.new(alert_callback: ->(e) { alert_called = true })

        error = StandardError.new('Server error')
        expect(LePain::Application.logger).to receive(:error)

        handler.handle(error)
        expect(alert_called).to be true
      end

      it 'logs client errors as info' do
        error = ArgumentError.new('Bad input')
        expect(LePain::Application.logger).to receive(:info)

        handler.handle(error)
      end

      it 'logs permanent errors and alerts ops' do
        alert_called = false
        handler = described_class.new(alert_callback: ->(_e) { alert_called = true })
        error = LePain::Errors::PermanentError::InvalidState.new('Invalid transition')

        expect(LePain::Application.logger).to receive(:error)

        handler.handle(error)
        expect(alert_called).to be true
      end
    end

    describe '#handle_operation' do
      let(:retry_policy) do
        LePain::RetryPolicy.new(max_attempts: 3, base_delay: 0, jitter: false)
      end

      it 'retries transient errors with backoff and returns successful result' do
        attempts = 0
        handler = described_class.new(retry_policy: retry_policy)

        result = handler.handle_operation do
          attempts += 1
          raise Timeout::Error, 'temporary timeout' if attempts < 3

          'ok'
        end

        expect(result).to eq('ok')
        expect(attempts).to eq(3)
      end

      it 'returns classified transient error after retries are exhausted' do
        attempts = 0
        handler = described_class.new(retry_policy: retry_policy)

        result = handler.handle_operation do
          attempts += 1
          raise Timeout::Error, 'still down'
        end

        expect(result).to be_a(LePain::Errors::TransientError::Timeout)
        expect(attempts).to eq(3)
      end

      it 'does not retry permanent errors' do
        attempts = 0
        handler = described_class.new(retry_policy: retry_policy)

        result = handler.handle_operation do
          attempts += 1
          raise LePain::Errors::PermanentError::BusinessRuleViolation, 'invalid transition'
        end

        expect(result).to be_a(LePain::Errors::PermanentError::BusinessRuleViolation)
        expect(attempts).to eq(1)
      end
    end
  end
end
