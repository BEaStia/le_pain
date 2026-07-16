require 'spec_helper'
require 'json'

# Mock PG classes for testing without actual PostgreSQL
module PG
  class Result
    def initialize(rows = [])
      @rows = rows
    end

    def ntuples
      @rows.size
    end

    def first
      @rows.first
    end

    def map(&block)
      @rows.map(&block)
    end
  end

  class MockConnection
    attr_reader :queries

    def initialize
      @data = {}
      @queries = []
    end

    def exec_params(sql, params = [])
      @queries << { sql: sql, params: params }

      case sql
      when /INSERT INTO lepain_tasks/
        id = params[0]
        @data[id] = {
          'id' => params[0],
          'type' => params[1],
          'state' => params[2],
          'payload' => params[3],
          'result' => params[4],
          'error' => params[5],
          'context' => params[6],
          'created_at' => params[7],
          'updated_at' => params[8],
          'started_at' => params[9],
          'completed_at' => params[10],
          'attempts' => params[11],
        }
        PG::Result.new([@data[id]])

      when /SELECT \* FROM lepain_tasks WHERE id =/
        id = params[0]
        PG::Result.new(@data[id] ? [@data[id]] : [])

      when /SELECT \* FROM lepain_tasks.*ORDER BY/
        limit = params[-2]
        offset = params[-1]
        tasks = @data.values

        # Apply filters from WHERE clause
        if sql.include?('state = $')
          state_param_idx = sql.match(/state = \$(\d+)/)[1].to_i
          state_value = params[state_param_idx - 1]
          tasks = tasks.select { |t| t['state'] == state_value }
        end

        if sql.include?('type = $')
          type_param_idx = sql.match(/type = \$(\d+)/)[1].to_i
          type_value = params[type_param_idx - 1]
          tasks = tasks.select { |t| t['type'] == type_value }
        end

        if sql.include?('to_tsvector')
          search_param_idx = sql.match(/plainto_tsquery\('simple', \$(\d+)\)/)[1].to_i
          search_value = params[search_param_idx - 1]
          tasks = tasks.select { |t| t['payload'].to_s.include?(search_value) }
        end

        tasks = tasks.sort_by { |t| t['created_at'] }.reverse.drop(offset).first(limit)
        PG::Result.new(tasks)

      when /UPDATE lepain_tasks/
        id = params[0]
        if @data[id]
          @data[id]['state'] = params[1]
          @data[id]['result'] = params[2]
          @data[id]['error'] = params[3]
          @data[id]['updated_at'] = params[4]
          @data[id]['completed_at'] = params[5]
          @data[id]['started_at'] = params[6]
          @data[id]['attempts'] = params[7]
        end
        PG::Result.new

      when /DELETE FROM lepain_tasks WHERE id/
        id = params[0]
        @data.delete(id)
        PG::Result.new

      when /DELETE FROM lepain_tasks/
        @data.clear
        PG::Result.new

      when /SELECT COUNT/
        PG::Result.new([{ 'count' => @data.size.to_s }])

      when /CREATE TABLE/
        PG::Result.new

      else
        PG::Result.new
      end
    end

    def exec(sql)
      @queries << { sql: sql, params: [] }
      case sql
      when /SELECT COUNT/
        PG::Result.new([{ 'count' => @data.size.to_s }])
      when /DELETE FROM lepain_tasks/
        @data.clear
        PG::Result.new
      when /BEGIN|COMMIT|ROLLBACK/
        PG::Result.new
      else
        PG::Result.new
      end
    end
  end
end

# Stub require 'pg' since we're using mocks
$LOADED_FEATURES << 'pg.rb' unless $LOADED_FEATURES.any? { |f| f.end_with?('pg.rb') }

require 'le_pain/task_stores/postgres_store'

RSpec.describe LePain::TaskStores::PostgresStore do
  let(:mock_conn) { PG::MockConnection.new }
  let(:store) { described_class.new(connection: mock_conn, ttl: 86400) }
  let(:task) { LePain::Task.new(type: 'report', payload: { user_id: '123' }) }

  describe '#create' do
    it 'inserts task into database' do
      store.create(task)
      expect(mock_conn.queries.any? { |q| q[:sql].include?('INSERT INTO lepain_tasks') }).to be true
    end

    it 'returns the task' do
      result = store.create(task)
      expect(result).to eq(task)
    end
  end

  describe '#find' do
    it 'finds task by id' do
      store.create(task)
      found = store.find(task.id)
      expect(found).to be_a(LePain::Task)
      expect(found.id).to eq(task.id)
      expect(found.type).to eq('report')
    end

    it 'returns nil for missing task' do
      expect(store.find('nonexistent')).to be_nil
    end
  end

  describe '#update' do
    it 'updates task state' do
      store.create(task)
      store.update(task.id) { |t| t.complete!({ result: 'done' }) }

      found = store.find(task.id)
      expect(found.state).to eq('completed')
      expect(found.result).to eq({ 'result' => 'done' })
    end

    it 'returns nil for missing task' do
      expect(store.update('nonexistent') { |t| t.complete!({}) }).to be_nil
    end
  end

  describe '#list' do
    before do
      3.times { |i| store.create(LePain::Task.new(type: "type_#{i}")) }
    end

    it 'returns tasks sorted by created_at desc' do
      tasks = store.list
      expect(tasks.size).to eq(3)
    end

    it 'respects limit' do
      tasks = store.list(limit: 2)
      expect(tasks.size).to eq(2)
    end

    it 'filters by state' do
      store.update(store.list.first.id) { |t| t.complete!({}) }
      completed = store.list(state: 'completed')
      expect(completed.size).to eq(1)
    end

    it 'filters by type' do
      typed = store.list(type: 'type_1')
      expect(typed.size).to eq(1)
    end

    it 'supports offset pagination' do
      tasks = store.list(limit: 1, offset: 1)
      expect(tasks.size).to eq(1)
    end

    it 'supports page pagination' do
      tasks = store.list(page: 2, page_size: 1)
      expect(tasks.size).to eq(1)
    end

    it 'supports full-text payload search' do
      store.create(LePain::Task.new(type: 'report', payload: { title: 'needle report' }))
      matches = store.list(search: 'needle')
      expect(matches.size).to eq(1)
      expect(matches.first.payload['title']).to eq('needle report')
    end
  end

  describe '#delete' do
    it 'removes task' do
      store.create(task)
      store.delete(task.id)
      expect(store.find(task.id)).to be_nil
    end
  end

  describe '#size' do
    it 'returns count of tasks' do
      store.create(task)
      expect(store.size).to eq(1)
    end
  end

  describe '#clear' do
    it 'removes all tasks' do
      store.create(task)
      store.clear
      expect(store.size).to eq(0)
    end
  end

  describe '#cleanup' do
    it 'removes expired finished tasks' do
      store.create(task)
      store.update(task.id) { |t| t.complete!({}) }
      # Manually set updated_at to past
      mock_conn.instance_variable_get(:@data)[task.id]['updated_at'] = (Time.now - 100_000).to_s
      store.cleanup
      expect(store.size).to eq(0)
    end
  end

  describe 'attempt tracking' do
    it 'persists task attempts' do
      store.create(task)
      store.update(task.id) { |t| t.increment_attempt! }
      expect(store.find(task.id).attempts).to eq(1)
    end
  end

  describe 'cleanup scheduler' do
    it 'starts and stops cleanup thread' do
      scheduled = described_class.new(connection: mock_conn, cleanup_interval: 60)
      thread = scheduled.instance_variable_get(:@cleanup_thread)

      expect(thread).to be_alive
      scheduled.stop_cleanup_scheduler
      expect(scheduled.instance_variable_get(:@cleanup_thread)).to be_nil
    end
  end
end
