require 'spec_helper'

RSpec.describe LePain::AsyncHandler do
  class RetrySpecFlakyJob
    class << self
      attr_accessor :calls

      def task_type = 'retry_spec_flaky'

      def process(_task)
        self.calls += 1
        raise Timeout::Error, 'temporary timeout' if calls < 3

        { ok: true }
      end
    end
  end

  class RetrySpecAlwaysTransientJob
    class << self
      attr_accessor :calls

      def task_type = 'retry_spec_always_transient'

      def process(_task)
        self.calls += 1
        raise Timeout::Error, 'still down'
      end
    end
  end

  class RetrySpecPermanentJob
    class << self
      attr_accessor :calls

      def task_type = 'retry_spec_permanent'

      def process(_task)
        self.calls += 1
        raise LePain::Errors::PermanentError::InvalidState, 'bad state'
      end
    end
  end

  class RetrySpecSuccessJob
    def self.task_type = 'retry_spec_success'

    def self.process(_task)
      { retried: true }
    end
  end

  before do
    described_class.instance_variable_set(:@jobs, {})
    described_class.task_store = LePain::TaskStores.resolve(:memory)
    described_class.dead_letter_store = LePain::TaskStores.resolve(:memory)
    described_class.retry_policy = LePain::RetryPolicy.new(max_attempts: 3, base_delay: 0, jitter: false)

    RetrySpecFlakyJob.calls = 0
    RetrySpecAlwaysTransientJob.calls = 0
    RetrySpecPermanentJob.calls = 0

    described_class.register(RetrySpecFlakyJob)
    described_class.register(RetrySpecAlwaysTransientJob)
    described_class.register(RetrySpecPermanentJob)
    described_class.register(RetrySpecSuccessJob)
  end

  describe '.execute' do
    it 'retries transient errors and completes the task' do
      task = LePain::Task.new(type: RetrySpecFlakyJob.task_type)

      result = described_class.execute(task)

      expect(result).to eq({ ok: true })
      expect(task.completed?).to be true
      expect(task.attempts).to eq(3)
      expect(RetrySpecFlakyJob.calls).to eq(3)
      expect(described_class.dead_letter_store.size).to eq(0)
    end

    it 'moves transient failures to the dead letter queue after max attempts' do
      task = LePain::Task.new(type: RetrySpecAlwaysTransientJob.task_type)

      expect { described_class.execute(task) }.to raise_error(LePain::Errors::TransientError::Timeout)

      dlq_task = described_class.dead_letter_store.find(task.id)
      expect(dlq_task).not_to be_nil
      expect(dlq_task.failed?).to be true
      expect(dlq_task.attempts).to eq(3)
      expect(RetrySpecAlwaysTransientJob.calls).to eq(3)
    end

    it 'does not retry permanent errors' do
      task = LePain::Task.new(type: RetrySpecPermanentJob.task_type)

      expect { described_class.execute(task) }.to raise_error(LePain::Errors::PermanentError::InvalidState)

      expect(task.failed?).to be true
      expect(task.attempts).to eq(1)
      expect(RetrySpecPermanentJob.calls).to eq(1)
      expect(described_class.dead_letter_store.find(task.id)).to eq(task)
    end
  end

  describe '.handle_request' do
    it 'lists dead letter tasks' do
      task = LePain::Task.new(type: RetrySpecPermanentJob.task_type)
      task.fail!(LePain::Errors::PermanentError::InvalidState.new('bad state'))
      described_class.dead_letter_store.create(task)

      request = LePain::Request.new(action: 'GET:/jobs/dead_letter')
      response = described_class.handle_request(request, nil)

      expect(response.status).to eq(200)
      expect(response.body[:total]).to eq(1)
      expect(response.body[:tasks].first['id']).to eq(task.id)
    end

    it 'retries a dead letter task' do
      allow(Thread).to receive(:new) { |&block| block.call }
      task = LePain::Task.new(type: RetrySpecSuccessJob.task_type)
      task.fail!(LePain::Errors::TransientError::Timeout.new('temporary timeout'))
      described_class.dead_letter_store.create(task)

      request = LePain::Request.new(
        action: "POST:/jobs/dead_letter/#{task.id}/retry",
        payload: { id: task.id }
      )
      response = described_class.handle_request(request, nil)

      expect(response.status).to eq(202)
      expect(described_class.dead_letter_store.find(task.id)).to be_nil
      expect(described_class.task_store.find(task.id).completed?).to be true
    end
  end
end
