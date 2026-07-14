require 'spec_helper'
require 'le_pain/migrations'

RSpec.describe LePain::Migrations::Migration do
  let(:migration) { described_class.new(version: '001', name: 'create_users', description: 'Create users table') }

  describe '#initialize' do
    it 'sets version, name, and description' do
      expect(migration.version).to eq('001')
      expect(migration.name).to eq('create_users')
      expect(migration.description).to eq('Create users table')
    end
  end

  describe '#up' do
    it 'raises NotImplementedError' do
      expect { migration.up(nil) }.to raise_error(NotImplementedError)
    end
  end

  describe '#down' do
    it 'raises NotImplementedError' do
      expect { migration.down(nil) }.to raise_error(NotImplementedError)
    end
  end

  describe '#to_h' do
    it 'returns hash representation' do
      hash = migration.to_h
      expect(hash[:version]).to eq('001')
      expect(hash[:name]).to eq('create_users')
      expect(hash[:description]).to eq('Create users table')
    end
  end
end

RSpec.describe LePain::Migrations::Runner do
  let(:mock_connection) do
    instance_double('PG::Connection').tap do |conn|
      allow(conn).to receive(:exec)
      allow(conn).to receive(:exec_params)
      allow(conn).to receive(:exec).with('SELECT version FROM schema_migrations ORDER BY version').and_return([])
    end
  end
  let(:runner) { described_class.new(connection: mock_connection, migrations_dir: '/nonexistent') }

  describe '#initialize' do
    it 'accepts connection and migrations_dir' do
      expect(runner).to be_a(described_class)
    end
  end

  describe '#migrate' do
    it 'ensures migrations table exists' do
      expect(mock_connection).to receive(:exec).with(/CREATE TABLE IF NOT EXISTS schema_migrations/)
      runner.migrate
    end

    it 'returns 0 when no migrations' do
      expect(runner.migrate).to eq(0)
    end
  end

  describe '#rollback' do
    it 'ensures migrations table exists' do
      expect(mock_connection).to receive(:exec).with(/CREATE TABLE IF NOT EXISTS schema_migrations/)
      runner.rollback
    end

    it 'returns 0 when no migrations to rollback' do
      expect(runner.rollback).to eq(0)
    end
  end

  describe '#status' do
    it 'ensures migrations table exists' do
      expect(mock_connection).to receive(:exec).with(/CREATE TABLE IF NOT EXISTS schema_migrations/)
      runner.status
    end

    it 'returns empty array when no migrations' do
      expect(runner.status).to eq([])
    end
  end

  describe '#pending_count' do
    it 'returns 0 when no migrations' do
      expect(runner.pending_count).to eq(0)
    end
  end
end
