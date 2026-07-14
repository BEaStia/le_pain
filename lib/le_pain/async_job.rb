# frozen_string_literal: true

module LePain
  class AsyncJob
    class << self
      def process(task)
        raise NotImplementedError, 'implement #process(task) in subclass'
      end

      def task_type
        name.sub(/Job$/, '').gsub(/([A-Z]+)([A-Z][a-z])/, '\1_\2').gsub(/([a-z\d])([A-Z])/, '\1_\2').downcase
      end
    end
  end
end
