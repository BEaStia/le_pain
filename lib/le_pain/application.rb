# frozen_string_literal: true

require 'uri'
require 'logger'
require 'yaml'
require_relative 'environment'

module LePain
  # Application class that loads all initializers, files and runs in loop
  class Application
    def self.env
      if @env
        @env
      else
        envs = config['environments']
        LePain::Environment.populate_environments(envs)
        @env ||= LePain::Environment.new(envs)
      end
    end

    class << self
      attr_writer :env

      def root
        @root ||= File.join(File.dirname(__FILE__), '..')
      end

      def config
        @config ||= YAML.load_file(File.join(Application.root, 'config', 'le_pain.yml'))
      end

      def logger
        unless @logger
          @logger = Logger.new(STDOUT)
          @logger.formatter = Logger::Formatter.new
        end
        @logger
      end
    end

    def initialize
      files = Dir.glob(File.join(self.class.root, 'config', 'initializers', '*.rb'))
      files.sort.each { |file| require file }
    end

    def self.run!
      Application.new.load
      logger.info('system started')
      loop { sleep 0.1 }
    end

    def load
      files = Dir.glob(File.join(self.class.root, 'config', 'post_initializers', '*.rb'))
      files.sort.each { |file| require file }
    end
  end
end
