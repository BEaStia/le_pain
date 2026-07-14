# frozen_string_literal: true

module LePain
  module TaskStores
    class Base
      def create(task); raise NotImplementedError; end
      def find(id); raise NotImplementedError; end
      def update(id, &block); raise NotImplementedError; end
      def delete(id); raise NotImplementedError; end
      def list(limit: 50, state: nil); raise NotImplementedError; end
      def cleanup; end
      def size; raise NotImplementedError; end
      def clear; raise NotImplementedError; end
    end
  end
end
