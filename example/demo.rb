#!/usr/bin/env ruby
# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path('../lib', __dir__)
require 'le_pain'
require_relative 'order_handler'
require_relative 'async_jobs'

LePain::Application.router.register('POST:/orders', OrderHandler)
LePain::Application.router.register('GET:/orders/:id', OrderHandler)
LePain::Application.router.register('orders.create', OrderHandler)
LePain::Application.router.register('orders.get', OrderHandler)

LePain::Application.router.idempotency(ttl: 300)

puts '=== LePain: Trace + Correlation + Idempotency + Async Jobs ==='
puts

puts '--- 1. HTTP request with trace/correlation IDs ---'
request = LePain::Request.from_http(
  method: 'POST',
  path: '/orders',
  body: { user_id: 'user-123', items: ['item-a', 'item-b'] },
  headers: {
    'x-request-id' => 'req-http-001',
    'x-trace-id' => 'trace-abc',
    'x-correlation-id' => 'corr-xyz',
    'idempotency-key' => 'idem-001',
  },
)

response = LePain::Application.router.dispatch(request)
puts "HTTP POST /orders => #{response.status}"
puts "  #{response.to_json}"
puts

puts '--- 2. Same idempotency key (retry) ---'
request2 = LePain::Request.from_http(
  method: 'POST',
  path: '/orders',
  body: { user_id: 'user-999', items: [] },
  headers: {
    'x-request-id' => 'req-http-002',
    'idempotency-key' => 'idem-001',
  },
)

response2 = LePain::Application.router.dispatch(request2)
puts "HTTP POST /orders (retry) => #{response2.status}"
puts "  #{response2.to_json}"
puts "  Same order_id? #{response.body['order_id'] == response2.body['order_id']}"
puts

puts '--- 3. MQ request with correlation propagation ---'
request3 = LePain::Request.from_mq(
  topic: 'orders.create',
  message: { user_id: 'user-456', items: ['item-c'] }.to_json,
  metadata: {
    request_id: 'req-mq-003',
    trace_id: 'trace-abc',
    correlation_id: 'corr-xyz',
  },
)

response3 = LePain::Application.router.dispatch(request3)
puts "MQ orders.create => #{response3.status}"
puts "  #{response3.to_json}"
puts

puts '--- 4. Async job submission ---'
LePain::Application.enable_async_processing

job_request = LePain::Request.from_http(
  method: 'POST',
  path: '/jobs',
  body: { type: 'order_report', user_id: 'user-123' },
  headers: { 'x-request-id' => 'req-job-001', 'x-trace-id' => 'trace-abc' },
)

job_response = LePain::Application.router.dispatch(job_request)
puts "POST /jobs => #{job_response.status}"
puts "  response.body class: #{job_response.body.class}"
puts "  response.body: #{job_response.body.inspect}"
task_data = job_response.body
puts "  task_id: #{task_data['id']}"
puts "  state: #{task_data['state']}"
puts

puts '--- 5. Poll job status ---'
sleep 3

status_request = LePain::Request.from_http(
  method: 'GET',
  path: '/jobs/' + task_data['id'],
  headers: { 'x-request-id' => 'req-status-001' },
)

status_response = LePain::Application.router.dispatch(status_request)
puts "GET /jobs/:id => #{status_response.status}"
puts "  state: #{status_response.body['state']}"
puts "  duration: #{status_response.body['duration']}s"
puts "  result: #{status_response.body['result']}"
puts

puts 'Done!'
