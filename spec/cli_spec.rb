require 'spec_helper'
require 'tmpdir'
require 'le_pain/cli'

RSpec.describe LePain::CLI do
  describe '#default_content' do
    let(:cli) { described_class.new }

    it 'generates Gemfile content' do
      content = cli.send(:default_content, 'Gemfile', binding)
      expect(content).to include("gem 'le_pain'")
      expect(content).to include("gem 'rake'")
    end

    it 'generates Rakefile content' do
      content = cli.send(:default_content, 'Rakefile', binding)
      expect(content).to include('RSpec::Core::RakeTask')
    end

    it 'generates config/le_pain.yml content' do
      content = cli.send(:default_content, 'config/le_pain.yml', binding)
      expect(content).to include('environments:')
      expect(content).to include('development:')
    end

    it 'generates bin/start_service.sh content' do
      content = cli.send(:default_content, 'bin/start_service.sh', binding)
      expect(content).to include('#!/bin/bash')
      expect(content).to include('bundle exec ruby service.rb')
    end

    it 'generates Dockerfile content' do
      content = cli.send(:default_content, 'Dockerfile', binding)
      expect(content).to include('FROM ruby:')
      expect(content).to include('bundle install')
    end

    it 'generates .gitignore content' do
      content = cli.send(:default_content, '.gitignore', binding)
      expect(content).to include('/.bundle/')
      expect(content).to include('/vendor/')
    end

    it 'generates handler content for custom handler names' do
      cli.instance_variable_set(:@handler_name, 'order')
      cli.instance_variable_set(:@handler_class, 'Order')

      content = cli.send(:default_content, 'handlers/order_handler.rb', binding)

      expect(content).to include('class OrderHandler < LePain::Handler')
      expect(content).to include("handle 'POST:/order'")
    end
  end

  describe '#run' do
    it 'runs application with runtime flags' do
      cli = described_class.new(%w[run --http-port 4567 --async --metrics])

      expect(LePain::Application).to receive(:run!).with(
        http_port: 4567,
        async: true,
        metrics: true,
        mq_client: nil
      )

      cli.run
    end
  end

  describe '#generate_component' do
    around do |example|
      Dir.mktmpdir do |dir|
        @tmpdir = dir
        Dir.chdir(dir) { example.run }
      end
    end

    it 'generates a handler and registers it in service.rb' do
      File.write('service.rb', <<~RUBY)
        # frozen_string_literal: true

        # Register handlers
      RUBY

      described_class.new(%w[generate handler order]).run

      expect(File.read('handlers/order_handler.rb')).to include('class OrderHandler < LePain::Handler')
      expect(File.read('service.rb')).to include("LePain::Application.router.register('POST:/order', OrderHandler)")
    end

    it 'generates a job and registers it in service.rb' do
      File.write('service.rb', <<~RUBY)
        # frozen_string_literal: true

        # Register jobs
      RUBY

      described_class.new(%w[generate job report]).run

      expect(File.read('jobs/report_job.rb')).to include('class ReportJob < LePain::AsyncJob')
      expect(File.read('service.rb')).to include('LePain::AsyncHandler.register(ReportJob)')
    end

    it 'uses templates from custom template directory' do
      template_dir = File.join(@tmpdir, 'templates')
      FileUtils.mkdir_p(File.join(template_dir, 'handlers'))
      File.write(File.join(template_dir, 'handlers/custom_handler.rb.erb'), "custom <%= @handler_name %>\n")

      described_class.new(['--template-dir', template_dir, 'generate', 'handler', 'custom']).run

      expect(File.read('handlers/custom_handler.rb')).to eq("custom custom\n")
    end
  end

  describe '#show_help' do
    it 'outputs help text' do
      cli = described_class.new
      expect { cli.send(:show_help) }.to output(/LePain CLI/).to_stdout
      expect { cli.send(:show_help) }.to output(/lepain run/).to_stdout
    end
  end

  describe '#show_version' do
    it 'outputs version' do
      cli = described_class.new
      expect { cli.send(:show_version) }.to output(/LePain #{LePain::VERSION}/).to_stdout
    end
  end
end
