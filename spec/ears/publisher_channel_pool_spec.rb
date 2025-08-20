require 'ears/publisher_channel_pool'

RSpec.describe Ears::PublisherChannelPool do
  let(:mock_connection) { instance_double(Bunny::Session) }
  let(:mock_channel) { instance_double(Bunny::Channel) }
  let(:mock_pool) { instance_double(ConnectionPool) }

  before do
    # Reset class state between tests
    described_class.instance_variable_set(:@channel_pool, nil)

    allow(Ears).to receive(:connection).and_return(mock_connection)
    allow(mock_connection).to receive(:create_channel).and_return(mock_channel)
    allow(ConnectionPool).to receive(:new).and_return(mock_pool)
  end

  describe '.with_channel' do
    it 'yields a channel from the pool' do
      expect(mock_pool).to receive(:with).and_yield(mock_channel)

      described_class.with_channel do |channel|
        expect(channel).to eq(mock_channel)
      end
    end

    it 'creates a connection pool with correct configuration' do
      allow(Ears.configuration).to receive_messages(
        publisher_pool_size: 16,
        publisher_pool_timeout: 3,
      )
      allow(mock_pool).to receive(:with)

      described_class.with_channel { |_channel| nil }

      expect(ConnectionPool).to have_received(:new).with(size: 16, timeout: 3)
    end

    it 'creates channels using Ears connection' do
      # Allow ConnectionPool to call the block we pass to it
      allow(ConnectionPool).to receive(:new).and_yield.and_return(mock_pool)
      allow(mock_pool).to receive(:with).and_yield(mock_channel)

      described_class.with_channel { |_channel| nil }

      expect(mock_connection).to have_received(:create_channel)
    end
  end

  describe '.reset!' do
    before do
      allow(mock_pool).to receive(:with)
      described_class.with_channel { |_channel| nil } # Initialize the pool
    end

    it 'resets the channel pool instance variable' do
      described_class.reset!
      expect(described_class.instance_variable_get(:@channel_pool)).to be_nil
    end

    it 'creates a new pool after reset' do
      described_class.reset!
      allow(mock_pool).to receive(:with)

      described_class.with_channel { |_channel| nil }

      expect(ConnectionPool).to have_received(:new).twice
    end
  end
end
