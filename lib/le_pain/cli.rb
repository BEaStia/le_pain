# frozen_string_literal: true

require 'fileutils'
require 'erb'

module LePain
  class CLI
    TEMPLATES_DIR = File.expand_path('cli/templates', __dir__)

    def initialize
      @command = ARGV[0]
      @args = ARGV[1..]
    end

    def run
      case @command
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
      puts "Generated handler: handlers/#{name}_handler.rb"
    end

    def generate_job(name)
      @job_name = name
      @job_class = name.split('_').map(&:capitalize).join
      generate_file('.', "jobs/#{name}_job.rb", binding)
      puts "Generated job: jobs/#{name}_job.rb"
    end

    def generate_service(name)
      @service_name = name
      @service_class = name.split('_').map(&:capitalize).join
      generate_file('.', "services/#{name}_service.rb", binding)
      puts "Generated service: services/#{name}_service.rb"
    end

    def generate_file(base_dir, relative_path, context, executable: false)
      template_path = File.join(TEMPLATES_DIR, "#{relative_path}.erb")
      target_path = File.join(base_dir, relative_path)

      if File.exist?(template_path)
        template = File.read(template_path)
        content = ERB.new(template, trim_mode: '-').result(context)
      else
        content = default_content(relative_path, context)
      end

      File.write(target_path, content)
      FileUtils.chmod(0o755, target_path) if executable
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
          lepain generate <type> <name> Generate a component
          lepain help                   Show this help
          lepain version                Show version

        Component types:
          handler, h    Generate a new handler
          job, j        Generate a new async job
          service, s    Generate a new service

        Examples:
          lepain new my-service
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
