require 'spec_helper'

RSpec.describe LePain::Metrics::Counter do
  let(:counter) { described_class.new(name: 'test_total', help: 'Test counter', labels: %w[method status]) }

  describe '#increment' do
    it 'increments the counter' do
      counter.increment({ 'method' => 'GET', 'status' => '200' })
      expect(counter.get({ 'method' => 'GET', 'status' => '200' })).to eq(1)
    end

    it 'increments by a specific amount' do
      counter.increment({ 'method' => 'GET', 'status' => '200' }, by: 5)
      expect(counter.get({ 'method' => 'GET', 'status' => '200' })).to eq(5)
    end
  end

  describe '#to_prometheus' do
    it 'outputs valid Prometheus format' do
      counter.increment({ 'method' => 'GET', 'status' => '200' })
      output = counter.to_prometheus
      expect(output).to include('# HELP test_total Test counter')
      expect(output).to include('# TYPE test_total counter')
      expect(output).to include('test_total{method="GET",status="200"} 1')
    end
  end
end

RSpec.describe LePain::Metrics::Gauge do
  let(:gauge) { described_class.new(name: 'active_connections', help: 'Active connections', labels: ['service']) }

  describe '#set' do
    it 'sets the gauge value' do
      gauge.set(42, { 'service' => 'api' })
      expect(gauge.get({ 'service' => 'api' })).to eq(42.0)
    end
  end

  describe '#increment / #decrement' do
    it 'increments and decrements' do
      gauge.set(10, { 'service' => 'api' })
      gauge.increment({ 'service' => 'api' }, by: 5)
      expect(gauge.get({ 'service' => 'api' })).to eq(15.0)
      gauge.decrement({ 'service' => 'api' }, by: 3)
      expect(gauge.get({ 'service' => 'api' })).to eq(12.0)
    end
  end

  describe '#to_prometheus' do
    it 'outputs valid Prometheus format' do
      gauge.set(42, { 'service' => 'api' })
      output = gauge.to_prometheus
      expect(output).to include('# HELP active_connections Active connections')
      expect(output).to include('# TYPE active_connections gauge')
      expect(output).to include('active_connections{service="api"} 42.0')
    end
  end
end

RSpec.describe LePain::Metrics::Histogram do
  let(:histogram) { described_class.new(name: 'request_duration', help: 'Request duration', labels: ['method'], buckets: [0.1, 0.5, 1.0]) }

  describe '#observe' do
    it 'records observations' do
      histogram.observe(0.3, { 'method' => 'GET' })
      histogram.observe(0.7, { 'method' => 'GET' })
      output = histogram.to_prometheus
      expect(output).to include('request_duration_bucket{method="GET",le="0.1"} 0')
      expect(output).to include('request_duration_bucket{method="GET",le="0.5"} 1')
      expect(output).to include('request_duration_bucket{method="GET",le="1.0"} 2')
      expect(output).to include('request_duration_sum{method="GET"} 1.0')
      expect(output).to include('request_duration_count{method="GET"} 2')
    end
  end

  describe '#time' do
    it 'measures block execution time' do
      result = histogram.time({ 'method' => 'POST' }) { sleep(0.01); 'done' }
      expect(result).to eq('done')
    end
  end
end

RSpec.describe LePain::Metrics::Summary do
  let(:summary) { described_class.new(name: 'request_size_bytes', help: 'Request size', labels: ['method'], quantiles: [0.5, 0.9]) }

  describe '#observe' do
    it 'records quantiles, sum, and count' do
      summary.observe(10, { 'method' => 'POST' })
      summary.observe(20, { 'method' => 'POST' })
      summary.observe(30, { 'method' => 'POST' })

      output = summary.to_prometheus
      expect(output).to include('# TYPE request_size_bytes summary')
      expect(output).to include('request_size_bytes{method="POST",quantile="0.5"} 20.0')
      expect(output).to include('request_size_bytes_sum{method="POST"} 60.0')
      expect(output).to include('request_size_bytes_count{method="POST"} 3')
    end
  end

  describe '#time' do
    it 'measures block execution time' do
      result = summary.time({ 'method' => 'GET' }) { 'done' }
      expect(result).to eq('done')
      expect(summary.to_prometheus).to include('request_size_bytes_count{method="GET"} 1')
    end
  end
end

RSpec.describe LePain::Metrics::Registry do
  let(:registry) { described_class.new }

  describe '#counter' do
    it 'creates and returns the same counter on repeated calls' do
      c1 = registry.counter('test', 'help')
      c2 = registry.counter('test', 'help')
      expect(c1).to eq(c2)
    end
  end

  describe '#to_prometheus' do
    it 'combines all metrics' do
      registry.counter('c1', 'help1').increment
      registry.gauge('g1', 'help2').set(10)
      output = registry.to_prometheus
      expect(output).to include('c1')
      expect(output).to include('g1')
    end
  end

  describe '#summary' do
    it 'creates and returns the same summary on repeated calls' do
      s1 = registry.summary('latency', 'Latency')
      s2 = registry.summary('latency', 'Latency')
      expect(s1).to eq(s2)
    end
  end

  describe 'thread safety' do
    it 'handles concurrent metric updates' do
      counter = registry.counter('concurrent_total', 'Concurrent counter')
      threads = 10.times.map do
        Thread.new do
          100.times { counter.increment }
        end
      end
      threads.each(&:join)

      expect(counter.get).to eq(1000)
    end
  end
end

RSpec.describe LePain::Metrics do
  before do
    described_class.instance_variable_set(:@registry, nil)
  end

  describe '.counter' do
    it 'returns a counter from the registry' do
      counter = described_class.counter('custom_counter', 'Custom counter')
      expect(counter).to be_a(LePain::Metrics::Counter)
    end
  end

  describe '.gauge' do
    it 'returns a gauge from the registry' do
      gauge = described_class.gauge('custom_gauge', 'Custom gauge')
      expect(gauge).to be_a(LePain::Metrics::Gauge)
    end
  end

  describe '.histogram' do
    it 'returns a histogram from the registry' do
      histogram = described_class.histogram('custom_histogram', 'Custom histogram')
      expect(histogram).to be_a(LePain::Metrics::Histogram)
    end
  end

  describe '.summary' do
    it 'returns a summary from the registry' do
      summary = described_class.summary('custom_summary', 'Custom summary')
      expect(summary).to be_a(LePain::Metrics::Summary)
    end
  end

  describe '.track_http_request' do
    it 'records HTTP metrics' do
      described_class.track_http_request(method: 'GET', path: '/test', status: 200, duration: 0.1)
      counter = described_class.registry.get('http_requests_total')
      expect(counter.get({ 'method' => 'GET', 'path' => '/test', 'status' => '200' })).to eq(1)
    end
  end

  describe '.track_mq_message' do
    it 'records MQ metrics' do
      described_class.track_mq_message(topic: 'orders', status: 'processed', duration: 0.2)
      counter = described_class.registry.get('mq_messages_total')
      expect(counter.get({ 'topic' => 'orders', 'status' => 'processed' })).to eq(1)
    end
  end

  describe '.to_prometheus' do
    it 'collects runtime metrics' do
      output = described_class.to_prometheus
      expect(output).to include('process_uptime_seconds')
      expect(output).to include('process_memory_bytes')
      expect(output).to include('metrics_registered_total')
    end
  end

  describe '.track_job' do
    it 'records job metrics' do
      described_class.track_job(type: 'report', status: 'completed', duration: 2.5)
      counter = described_class.registry.get('jobs_total')
      expect(counter.get({ 'type' => 'report', 'status' => 'completed' })).to eq(1)
    end
  end

  describe '.increment_active_jobs / .decrement_active_jobs' do
    it 'tracks active jobs' do
      described_class.increment_active_jobs
      expect(described_class.registry.get('active_jobs').get).to eq(1)
      described_class.decrement_active_jobs
      expect(described_class.registry.get('active_jobs').get).to eq(0)
    end
  end
end

RSpec.describe LePain::MetricsHandler do
  after do
    described_class.auth_token = nil
  end

  it 'returns Prometheus text format' do
    request = LePain::Request.new(action: 'GET:/metrics')
    response = described_class.handle_request(request, nil)

    expect(response.status).to eq(200)
    expect(response.headers['Content-Type']).to include('text/plain')
    expect(response.body).to include('# HELP')
  end

  it 'requires auth token when configured' do
    described_class.auth_token = 'secret'

    unauthorized = described_class.handle_request(LePain::Request.new(action: 'GET:/metrics'), nil)
    authorized = described_class.handle_request(
      LePain::Request.new(action: 'GET:/metrics', headers: { 'x-metrics-token' => 'secret' }),
      nil
    )

    expect(unauthorized.status).to eq(401)
    expect(authorized.status).to eq(200)
  end
end

RSpec.describe 'automatic metrics integration' do
  before do
    LePain::Metrics.instance_variable_set(:@registry, nil)
  end

  it 'tracks MQ messages through router dispatch' do
    router = LePain::Router.new
    router.route('orders.created') { |_req, _ctx| LePain::Response.success({ ok: true }) }

    router.dispatch(LePain::Request.new(action: 'orders.created', transport: :mq))

    counter = LePain::Metrics.registry.get('mq_messages_total')
    expect(counter.get({ 'topic' => 'orders.created', 'status' => 'processed' })).to eq(1)
  end

  it 'auto-registers metrics route when enabled' do
    router = LePain::Router.new
    allow(LePain::Application).to receive(:router).and_return(router)
    allow(LePain::Application).to receive(:config).and_return('metrics' => { 'auth_token' => 'secret' })
    LePain::Application.instance_variable_set(:@metrics_enabled, nil)

    LePain::Application.enable_metrics

    expect(router.routes).to include('GET:/metrics')
    expect(LePain::MetricsHandler.auth_token).to eq('secret')
  end
end
