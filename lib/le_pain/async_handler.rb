# frozen_string_literal: true

require_relative 'errors'
require_relative 'retry_policy'

module LePain
  class AsyncHandler
    class << self
      def task_store
        @task_store ||= TaskStores.resolve(:memory)
      end

      def task_store=(store)
        @task_store = store
      end

      def dead_letter_store
        @dead_letter_store ||= TaskStores.resolve(:memory)
      end

      def dead_letter_store=(store)
        @dead_letter_store = store
      end

      def retry_policy
        @retry_policy ||= RetryPolicy.new
      end

      def retry_policy=(policy)
        @retry_policy = policy
      end

      def register(job_class)
        @jobs ||= {}
        @jobs[job_class.task_type] = job_class
      end

      def jobs
        @jobs ||= {}
      end

      def submit(type:, payload:, context: nil)
        task = Task.new(type: type, payload: payload, context: context)
        task_store.create(task)
        task.start!

        Thread.new do
          ctx = context.is_a?(Context) ? context : nil
          Context.with(ctx) do
            execute(task)
          end
        rescue StandardError => e
          task.fail!(e)
          req_id = context.is_a?(Context) ? context.request_id : context&.dig('request_id')
          LePain::Application.logger.error("[#{req_id}] task #{task.id} failed: #{e.message}")
        end

        task
      end

      def execute(task)
        job_class = jobs[task.type]
        raise "unknown job type: #{task.type}" unless job_class

        task.start! unless task.running?
        req_id = request_id_for(task.context)
        LePain::Application.logger.info("[#{req_id}] executing task #{task.id} (#{task.type})")
        LePain::Metrics.increment_active_jobs
        active_job_tracked = true

        loop do
          task.increment_attempt!

          begin
            result = LePain::Metrics.registry.histogram('job_duration_seconds', 'Job execution duration', labels: ['type'])
              .time(type: task.type) { job_class.process(task) }
            task.complete!(result)
            LePain::Application.logger.info("[#{req_id}] task #{task.id} completed in #{task.duration}s")
            LePain::Metrics.track_job(type: task.type, status: 'completed', duration: task.duration)
            return result
          rescue StandardError => e
            classified = classify_error(e, task)

            unless retryable_error?(classified) && task.attempts < retry_policy.max_attempts
              move_to_dead_letter(task, classified)
              LePain::Metrics.track_job(type: task.type, status: 'failed', duration: task.duration || 0)
              raise classified
            end

            delay = retry_policy.calculate_delay(task.attempts)
            LePain::Application.logger.info(
              "[#{req_id}] retrying task #{task.id} attempt #{task.attempts}/#{retry_policy.max_attempts} after #{delay.round(2)}s (error: #{classified.message})"
            )
            sleep(delay)
          end
        end
      ensure
        LePain::Metrics.decrement_active_jobs if active_job_tracked
      end

      def handle_request(request, context)
        case request.action
        when 'POST:/jobs'
          type = request['type'] || request['job_type']
          raise LePain::ConfigurationError, 'type is required' unless type
          raise LePain::ConfigurationError, "unknown job type: #{type}" unless jobs[type]

          task = submit(type: type, payload: request.payload.reject { |k, _| %w[type job_type].include?(k) }, context: context)
          Response.success(task.to_h, status: 201)

        when 'GET:/jobs/dead_letter'
          tasks = dead_letter_store.list(limit: request['limit']&.to_i || 20, state: request['state'])
          Response.success({ tasks: tasks.map(&:to_h), total: tasks.size })

        when /\APOST:\/jobs\/dead_letter\/[^\/]+\/retry\z/
          task_id = request['id'] || request.fetch('id')
          task = dead_letter_store.find(task_id)
          return Response.not_found("dead letter task #{task_id} not found") unless task

          retry_dead_letter(task, context)
          Response.success(task.to_h, status: 202)

        when /\AGET:\/jobs\/[^\/]+\z/
          task_id = request['id'] || request.fetch('id')
          task = task_store.find(task_id)
          return Response.not_found("task #{task_id} not found") unless task

          Response.success(task.to_h)

        when 'GET:/jobs'
          tasks = task_store.list(limit: request['limit']&.to_i || 20, state: request['state'])
          Response.success({ tasks: tasks.map(&:to_h), total: tasks.size })

        else
          Response.not_found("no route for #{request.action}")
        end
      rescue LePain::ConfigurationError => e
        Response.bad_request(e.message)
      rescue StandardError => e
        LePain::Application.logger.error("async handler error: #{e.message}")
        Response.error(e.message, status: 500)
      end

      private

      def retry_dead_letter(task, context)
        dead_letter_store.delete(task.id)
        task.reset_for_retry!
        task_store.create(task)
        task.start!

        Thread.new do
          ctx = context.is_a?(Context) ? context : nil
          Context.with(ctx) { execute(task) }
        rescue StandardError => e
          task.fail!(e)
          LePain::Application.logger.error("[#{request_id_for(context)}] task #{task.id} failed: #{e.message}")
        end
      end

      def move_to_dead_letter(task, error)
        task.fail!(error)
        dead_letter_store.create(task)
        LePain::Application.logger.error(
          "[#{request_id_for(task.context)}] task #{task.id} moved to dead letter queue: #{error.message}"
        )
      end

      def classify_error(error, task)
        Errors::Handler.new.handle(error, context: context_hash(task.context))
      end

      def retryable_error?(error)
        error.respond_to?(:retryable?) && error.retryable?
      end

      def context_hash(context)
        if context.is_a?(Context)
          {
            request_id: context.request_id,
            trace_id: context.trace_id,
            correlation_id: context.correlation_id,
          }
        elsif context.respond_to?(:to_h)
          h = context.to_h
          {
            request_id: h[:request_id] || h['request_id'],
            trace_id: h[:trace_id] || h['trace_id'],
            correlation_id: h[:correlation_id] || h['correlation_id'],
          }
        else
          {}
        end
      end

      def request_id_for(context)
        context_hash(context)[:request_id]
      end
    end
  end
end
