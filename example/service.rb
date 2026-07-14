# frozen_string_literal: true

require 'le_pain'
require_relative 'order_handler'

LePain::Application.configure do |app|
  app.router.register('POST:/orders', OrderHandler)
  app.router.register('GET:/orders/:id', OrderHandler)
  app.router.register('orders.create', OrderHandler)
  app.router.register('orders.get', OrderHandler)

  app.health_check.register('database') do
    { connected: true }
  end
end

LePain::Application.run!(http_port: 3000)
