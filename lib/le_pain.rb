require 'le_pain/version'
require 'le_pain/environment'
require 'le_pain/application'

Dir["tasks/**/*.rake"].each { |ext| load ext }

module LePain
  class EnvironmentNotSetError < StandardError; end
end
