# frozen_string_literal: true

require 'fileutils'
require 'erb'

module LePain
  class CLI
    TEMPLATES_DIR = File.expand_path('cli/templates', __dir__)

    def initialize(argv = ARGV)
      @argv = argv.dup
      @template_dir = extract_option('--template-dir')
      @command = @argv[0]
      @args = @argv[1..] || []
    end

    def run
      case @command
      when 'run'
        run_service
      when 'new'
        generate_new_service
      when 'generate', 'g'
        generate_component
      when 'help', '-h', '--help', nil
        show_help
      when 'version', '-v', '--version'
        show_version
      else
        puts "Unknown command: #{@command}"
        show_help
        exit 1
      end
    end

    private

    def extract_option(name)
      index = @argv.index(name)
      return unless index

      value = @argv[index + 1]
      @argv.slice!(index, 2)
      value
    end

    def flag?(name)
      !!@args.delete(name)
    end

    def option(name)
      index = @args.index(name)
      return unless index

      value = @args[index + 1]
      @args.slice!(index, 2)
      value
    end

    def run_service
      http_port = option('--http-port')&.to_i
      async = flag?('--async')
      metrics = flag?('--metrics')
      mq_client = build_mq_client(option('--mq'))

      LePain::Application.run!(
        http_port: http_port,
        async: async,
        metrics: metrics,
        mq_client: mq_client
      )
    end

    def build_mq_client(name)
      return unless name

      require_relative 'transports'
      require_relative 'transports/mq_clients'

      case name
      when 'kafka'
        config = LePain::Application.config.dig('mq', 'kafka') || {}
        LePain::Transports::KafkaClient.new(
          brokers: config['brokers'] || ['localhost:9092'],
          group_id: config['group_id'] || 'lepain'
        )
      when 'nats'
        config = LePain::Application.config.dig('mq', 'nats') || {}
        LePain::Transports::NatsClient.new(url: config['url'] || 'nats://localhost:4222')
      when 'rmq'
        config = LePain::Application.config.dig('mq', 'rmq') || {}
        LePain::Transports::RmqClient.new(url: config['url'] || 'amqp://localhost:5672')
      else
        puts "Unknown message queue: #{name}"
        exit 1
      end
    end

    def generate_new_service
      service_name = @args[0]
      unless service_name
        puts 'Usage: lepain new <service_name>'
        exit 1
      end

      puts "Creating new service: #{service_name}"

      service_dir = File.join(Dir.pwd, service_name)
      if File.exist?(service_dir)
        puts "Error: Directory #{service_name} already exists"
        exit 1
      end

      FileUtils.mkdir_p(service_dir)

      # Create directory structure
      dirs = %w[
        config/initializers
        config/post_initializers
        handlers
        jobs
        services
        bin
        spec
      ]
      dirs.each { |dir| FileUtils.mkdir_p(File.join(service_dir, dir)) }

      # Generate files
      generate_file(service_dir, 'Gemfile', binding)
      generate_file(service_dir, 'Rakefile', binding)
      generate_file(service_dir, 'config/le_pain.yml', binding)
      generate_file(service_dir, 'bin/start_service.sh', binding, executable: true)
      generate_file(service_dir, 'handlers/example_handler.rb', binding)
      generate_file(service_dir, 'jobs/example_job.rb', binding)
      generate_file(service_dir, 'services/example_service.rb', binding)
      generate_file(service_dir, 'service.rb', binding)
      generate_file(service_dir, 'spec/spec_helper.rb', binding)
      generate_file(service_dir, 'Dockerfile', binding)
      generate_file(service_dir, '.gitignore', binding)

      puts "Service created at: #{service_dir}"
      puts
      puts 'Next steps:'
      puts "  cd #{service_name}"
      puts '  bundle install'
      puts '  bundle exec ruby service.rb'
    end

    def generate_component
      component_type = @args[0]
      component_name = @args[1]

      unless component_type && component_name
        puts 'Usage: lepain generate <handler|job|service> <name>'
        exit 1
      end

      case component_type
      when 'handler', 'h'
        generate_handler(component_name)
      when 'job', 'j'
        generate_job(component_name)
      when 'service', 's'
        generate_service(component_name)
      else
        puts "Unknown component type: #{component_type}"
        exit 1
      end
    end

    def generate_handler(name)
      @handler_name = name
      @handler_class = name.split('_').map(&:capitalize).join
      generate_file('.', "handlers/#{name}_handler.rb", binding)
      register_handler(name)
      puts "Generated handler: handlers/#{name}_handler.rb"
    end

    def generate_job(name)
      @job_name = name
      @job_class = name.split('_').map(&:capitalize).join
      generate_file('.', "jobs/#{name}_job.rb", binding)
      register_job(name)
      puts "Generated job: jobs/#{name}_job.rb"
    end

    def generate_service(name)
      @service_name = name
      @service_class = name.split('_').map(&:capitalize).join
      generate_file('.', "services/#{name}_service.rb", binding)
      puts "Generated service: services/#{name}_service.rb"
    end

    def generate_file(base_dir, relative_path, context, executable: false)
      template_path = template_path_for(relative_path)
      target_path = File.join(base_dir, relative_path)

      if File.exist?(template_path)
        template = File.read(template_path)
        content = ERB.new(template, trim_mode: '-').result(context)
      else
        content = default_content(relative_path, context)
      end

      FileUtils.mkdir_p(File.dirname(target_path))
      File.write(target_path, content)
      FileUtils.chmod(0o755, target_path) if executable
    end

    def template_path_for(relative_path)
      custom_path = File.join(@template_dir, "#{relative_path}.erb") if @template_dir
      return custom_path if custom_path && File.exist?(custom_path)

      File.join(TEMPLATES_DIR, "#{relative_path}.erb")
    end

    def register_handler(name)
      service_file = File.join(Dir.pwd, 'service.rb')
      return unless File.exist?(service_file)

      class_name = "#{name.split('_').map(&:capitalize).join}Handler"
      line = "LePain::Application.router.register('POST:/#{name}', #{class_name})"
      insert_registration(service_file, '# Register handlers', line)
    end

    def register_job(name)
      service_file = File.join(Dir.pwd, 'service.rb')
      return unless File.exist?(service_file)

      class_name = "#{name.split('_').map(&:capitalize).join}Job"
      insert_registration(service_file, '# Register jobs', "LePain::AsyncHandler.register(#{class_name})")
    end

    def insert_registration(path, marker, line)
      content = File.read(path)
      return if content.include?(line)

      lines = content.lines
      marker_index = lines.index { |candidate| candidate.strip == marker }

      if marker_index
        insert_at = marker_index + 1
        insert_at += 1 while lines[insert_at]&.strip&.start_with?('LePain::')
        lines.insert(insert_at, "#{line}\n")
      else
        lines << "\n#{marker}\n#{line}\n"
      end

      File.write(path, lines.join)
    end

    def default_content(path, context)
      case path
      when 'Gemfile'
        <<~RUBY
          source 'https://rubygems.org'

          gem 'le_pain'
          gem 'rake'
          gem 'rspec'
        RUBY
      when 'Rakefile'
        <<~RUBY
          require 'bundler/gem_tasks'
          require 'rspec/core/rake_task'

          RSpec::Core::RakeTask.new(:spec)

          task default: :spec
        RUBY
      when 'config/le_pain.yml'
        <<~YAML
          environments:
            development:
              default: true
            staging:
            production:

          logger:
            level: debug
            format: text
            output: stdout

          health_check:
            enabled: true
            port: 3001

          task_store:
            type: memory
            options:
              ttl: 86400
        YAML
      when 'bin/start_service.sh'
        <<~BASH
          #!/bin/bash
          set -e

          cd /app
          bundle exec ruby service.rb
        BASH
      when 'handlers/example_handler.rb'
        <<~RUBY
          # frozen_string_literal: true

          class ExampleHandler < LePain::Handler
            handle 'POST:/example' do |request, context|
              LePain::Response.success({ message: 'Hello from ExampleHandler' })
            end
          end
        RUBY
      when %r{\Ahandlers/.+_handler\.rb\z}
        <<~RUBY
          # frozen_string_literal: true

          class #{@handler_class}Handler < LePain::Handler
            handle 'POST:/#{@handler_name}' do |request, context|
              LePain::Response.success({ message: 'Hello from #{@handler_class}Handler' })
            end
          end
        RUBY
      when 'jobs/example_job.rb'
        <<~RUBY
          # frozen_string_literal: true

          class ExampleJob < LePain::AsyncJob
            def self.process(task)
              LePain::Application.logger.info("Processing example job")
              { result: 'done' }
            end
          end
        RUBY
      when %r{\Ajobs/.+_job\.rb\z}
        <<~RUBY
          # frozen_string_literal: true

          class #{@job_class}Job < LePain::AsyncJob
            def self.process(task)
              LePain::Application.logger.info("Processing #{@job_name} job")
              { result: 'done' }
            end
          end
        RUBY
      when 'services/example_service.rb'
        <<~RUBY
          # frozen_string_literal: true

          class ExampleService
            def self.do_something
              LePain::Application.logger.info("Doing something")
              { status: 'ok' }
            end
          end
        RUBY
      when %r{\Aservices/.+_service\.rb\z}
        <<~RUBY
          # frozen_string_literal: true

          class #{@service_class}Service
            def self.call
              { status: 'ok' }
            end
          end
        RUBY
      when 'service.rb'
        <<~RUBY
          # frozen_string_literal: true

          require 'le_pain'

          # Load handlers
          Dir[File.join(__dir__, 'handlers', '*.rb')].each { |f| require f }

          # Load jobs
          Dir[File.join(__dir__, 'jobs', '*.rb')].each { |f| require f }

          # Register handlers
          LePain::Application.router.register('POST:/example', ExampleHandler)

          # Register jobs
          LePain::AsyncHandler.register(ExampleJob)

          # Start service
          LePain::Application.run!(http_port: 3000, async: true)
        RUBY
      when 'spec/spec_helper.rb'
        <<~RUBY
          require 'bundler/setup'
          require 'le_pain'
          require 'le_pain/test'

          RSpec.configure do |config|
            config.include LePain::Test::Helpers
            config.include LePain::Test::Matchers
          end
        RUBY
      when 'Dockerfile'
        <<~DOCKER
          FROM ruby:3.2-slim

          RUN apt-get update -qq && apt-get install -y build-essential

          WORKDIR /app

          COPY Gemfile* ./
          RUN bundle install

          COPY . .

          CMD ["bin/start_service.sh"]
        DOCKER
      when '.gitignore'
        <<~GITIGNORE
          /.bundle/
          /vendor/
          /tmp/
          /log/
          *.log
          .env
        GITIGNORE
      else
        "# Generated by LePain CLI\n"
      end
    end

    def show_help
      puts <<~HELP
        LePain CLI - Microservice Framework

        Usage:
          lepain new <service_name>     Create a new service
          lepain run [options]          Run a service
          lepain generate <type> <name> Generate a component
          lepain help                   Show this help
          lepain version                Show version

        Run options:
          --http-port PORT              Start HTTP adapter on PORT
          --async                       Enable async job routes
          --metrics                     Enable metrics endpoint
          --mq kafka|nats|rmq           Start message queue adapter
          --template-dir DIR            Use custom generator templates

        Component types:
          handler, h    Generate a new handler
          job, j        Generate a new async job
          service, s    Generate a new service

        Examples:
          lepain new my-service
          lepain run --http-port 3000 --async --metrics
          lepain generate handler order
          lepain generate job report
          lepain generate service user
      HELP
    end

    def show_version
      puts "LePain #{LePain::VERSION}"
    end
  end
end
