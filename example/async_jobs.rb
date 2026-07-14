# frozen_string_literal: true

require 'le_pain'

class OrderReportJob < LePain::AsyncJob
  def self.process(task)
    ctx = task.context
    req_id = ctx.is_a?(LePain::Context) ? ctx.request_id : ctx&.dig('request_id')
    LePain::Application.logger.info("[#{req_id}] generating report for #{task.payload['user_id']}")
    sleep 2
    {
      report_id: SecureRandom.uuid,
      user_id: task.payload['user_id'],
      rows: 150,
      format: 'csv',
      url: '/reports/download/abc123',
    }
  end
end

class DataExportJob < LePain::AsyncJob
  def self.process(task)
    ctx = task.context
    req_id = ctx.is_a?(LePain::Context) ? ctx.request_id : ctx&.dig('request_id')
    LePain::Application.logger.info("[#{req_id}] exporting data: #{task.payload['format']}")
    sleep 1
    {
      export_id: SecureRandom.uuid,
      format: task.payload['format'],
      records: 10_000,
      file_size_mb: 42,
    }
  end
end

LePain::AsyncHandler.register(OrderReportJob)
LePain::AsyncHandler.register(DataExportJob)
