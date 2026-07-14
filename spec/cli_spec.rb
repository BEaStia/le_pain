require 'spec_helper'
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
  end

  describe '#show_help' do
    it 'outputs help text' do
      cli = described_class.new
      expect { cli.send(:show_help) }.to output(/LePain CLI/).to_stdout
    end
  end

  describe '#show_version' do
    it 'outputs version' do
      cli = described_class.new
      expect { cli.send(:show_version) }.to output(/LePain #{LePain::VERSION}/).to_stdout
    end
  end
end
