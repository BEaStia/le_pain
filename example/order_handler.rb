# frozen_string_literal: true

require 'le_pain'

class OrderService
  def self.create_order(user_id:, items:, context: nil)
    context ||= Context.current
    order_id = SecureRandom.uuid
    LePain::Application.logger.info("[#{context.request_id}] created order #{order_id} for user #{user_id} via #{context.transport}")
    { order_id: order_id, user_id: user_id, items: items, status: 'created', trace_id: context.trace_id }
  end

  def self.get_order(order_id, context: nil)
    context ||= Context.current
    LePain::Application.logger.info("[#{context.request_id}] fetching order #{order_id}")
    { order_id: order_id, status: 'found', items: ['item1', 'item2'] }
  end
end

class OrderHandler < LePain::Handler
  handle 'POST:/orders' do |request, context|
    result = OrderService.create_order(
      user_id: request['user_id'],
      items: request['items'] || [],
      context: context,
    )
    LePain::Response.success(result, status: 201)
  end

  handle 'GET:/orders/:id' do |_request, context|
    LePain::Response.success({ request_id: context.request_id, transport: context.transport })
  end

  handle 'orders.create' do |request, context|
    result = OrderService.create_order(
      user_id: request['user_id'],
      items: request['items'] || [],
      context: context,
    )
    LePain::Response.success(result)
  end

  handle 'orders.get' do |request, context|
    result = OrderService.get_order(request['order_id'], context: context)
    LePain::Response.success(result)
  end
end
