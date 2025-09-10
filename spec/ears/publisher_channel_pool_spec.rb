require 'ears/publisher_channel_pool'

RSpec.describe Ears::PublisherChannelPool do
  let(:mock_connection) { instance_double(Bunny::Session) }
  let(:mock_channel) do
    instance_double(Bunny::Channel, close: nil, confirm_select: nil)
  end
  let(:mock_standard_pool) { instance_double(ConnectionPool, shutdown: nil) }
  let(:mock_confirms_pool) { instance_double(ConnectionPool, shutdown: nil) }

  before do
    described_class.instance_variable_set(:@standard_pool, nil)
    described_class.instance_variable_set(:@confirms_pool, nil)
    described_class.instance_variable_set(:@creator_pid, nil)

    allow(Ears).to receive(:connection).and_return(mock_connection)
    allow(mock_connection).to receive(:create_channel).and_return(mock_channel)
  end

  describe '.with_channel' do
    context 'with confirms: false (default)' do
      it 'yields a channel from the standard pool' do
        allow(ConnectionPool).to receive(:new).and_return(mock_standard_pool)
        expect(mock_standard_pool).to receive(:with).and_yield(mock_channel)

        described_class.with_channel do |channel|
          expect(channel).to eq(mock_channel)
        end
      end

      it 'creates a connection pool with correct configuration for standard pool' do
        allow(Ears.configuration).to receive_messages(
          publisher_pool_size: 16,
          publisher_pool_timeout: 3,
        )
        allow(ConnectionPool).to receive(:new).and_return(mock_standard_pool)
        allow(mock_standard_pool).to receive(:with)

        described_class.with_channel(confirms: false) { |_channel| nil }

        expect(ConnectionPool).to have_received(:new).with(size: 16, timeout: 3)
      end

      it 'does not call confirm_select on channels' do
        allow(ConnectionPool).to receive(:new).and_yield.and_return(
          mock_standard_pool,
        )
        allow(mock_standard_pool).to receive(:with).and_yield(mock_channel)

        described_class.with_channel(confirms: false) { |_channel| nil }

        expect(mock_channel).not_to have_received(:confirm_select)
      end
    end

    context 'with confirms: true' do
      it 'yields a channel from the confirms pool' do
        allow(ConnectionPool).to receive(:new).and_return(mock_confirms_pool)
        expect(mock_confirms_pool).to receive(:with).and_yield(mock_channel)

        described_class.with_channel(confirms: true) do |channel|
          expect(channel).to eq(mock_channel)
        end
      end

      it 'creates a connection pool with correct configuration for confirms pool' do
        allow(Ears.configuration).to receive_messages(
          publisher_pool_size: 16,
          publisher_pool_timeout: 3,
          publisher_confirms_pool_size: 32,
        )
        allow(ConnectionPool).to receive(:new).and_return(mock_confirms_pool)
        allow(mock_confirms_pool).to receive(:with)

        described_class.with_channel(confirms: true) { |_channel| nil }

        expect(ConnectionPool).to have_received(:new).with(size: 32, timeout: 3)
      end

      it 'falls back to standard pool size when confirms pool size not configured' do
        allow(Ears.configuration).to receive_messages(
          publisher_pool_size: 16,
          publisher_pool_timeout: 3,
        )
        allow(Ears.configuration).to receive(:respond_to?).with(
          :publisher_confirms_pool_size,
        ).and_return(false)
        allow(ConnectionPool).to receive(:new).and_return(mock_confirms_pool)
        allow(mock_confirms_pool).to receive(:with)

        described_class.with_channel(confirms: true) { |_channel| nil }

        expect(ConnectionPool).to have_received(:new).with(size: 16, timeout: 3)
      end

      it 'calls confirm_select on channels' do
        allow(ConnectionPool).to receive(:new).and_yield.and_return(
          mock_confirms_pool,
        )
        allow(mock_confirms_pool).to receive(:with).and_yield(mock_channel)

        described_class.with_channel(confirms: true) { |_channel| nil }

        expect(mock_channel).to have_received(:confirm_select)
      end
    end

    it 'creates channels using Ears connection' do
      allow(ConnectionPool).to receive(:new).and_yield.and_return(
        mock_standard_pool,
      )
      allow(mock_standard_pool).to receive(:with).and_yield(mock_channel)

      described_class.with_channel { |_channel| nil }

      expect(mock_connection).to have_received(:create_channel)
    end

    it 'reuses existing pools on subsequent calls' do
      allow(ConnectionPool).to receive(:new).and_return(
        mock_standard_pool,
        mock_confirms_pool,
      )
      allow(mock_standard_pool).to receive(:with)
      allow(mock_confirms_pool).to receive(:with)

      described_class.with_channel(confirms: false) { |_channel| nil }
      described_class.with_channel(confirms: false) { |_channel| nil }
      described_class.with_channel(confirms: true) { |_channel| nil }
      described_class.with_channel(confirms: true) { |_channel| nil }

      expect(ConnectionPool).to have_received(:new).twice
    end

    it 'recreates pools after fork' do
      allow(ConnectionPool).to receive(:new).and_return(mock_standard_pool)
      allow(mock_standard_pool).to receive(:with)
      allow(described_class).to receive(:reset!).and_call_original

      described_class.with_channel { |_channel| nil }

      # Simulate fork by changing the creator PID
      described_class.instance_variable_set(:@creator_pid, Process.pid - 1)

      described_class.with_channel { |_channel| nil }

      expect(described_class).to have_received(:reset!)
    end

    it 'is thread-safe during initialization' do
      allow(mock_standard_pool).to receive(:with)
      allow(mock_confirms_pool).to receive(:with)
      threads = []
      pool_creation_count = 0

      allow(ConnectionPool).to receive(:new) do
        pool_creation_count += 1
        pool_creation_count.odd? ? mock_standard_pool : mock_confirms_pool
      end

      # Test concurrent access to both pool types
      10.times do |i|
        threads << Thread.new do
          described_class.with_channel(confirms: i.even?) { |_channel| nil }
        end
      end

      threads.each(&:join)

      expect(pool_creation_count).to eq(2)
    end
  end

  describe '.reset!' do
    before do
      allow(ConnectionPool).to receive(:new).and_return(
        mock_standard_pool,
        mock_confirms_pool,
      )
      allow(mock_standard_pool).to receive(:with)
      allow(mock_confirms_pool).to receive(:with)

      described_class.with_channel(confirms: false) { |_channel| nil }
      described_class.with_channel(confirms: true) { |_channel| nil }
    end

    it 'resets both pool instance variables' do
      described_class.reset!

      expect(described_class.instance_variable_get(:@standard_pool)).to be_nil
      expect(described_class.instance_variable_get(:@confirms_pool)).to be_nil
    end

    it 'creates new pools after reset' do
      described_class.reset!

      allow(ConnectionPool).to receive(:new).and_return(
        mock_standard_pool,
        mock_confirms_pool,
      )
      allow(mock_standard_pool).to receive(:with)
      allow(mock_confirms_pool).to receive(:with)

      described_class.with_channel(confirms: false) { |_channel| nil }
      described_class.with_channel(confirms: true) { |_channel| nil }

      expect(ConnectionPool).to have_received(:new).exactly(4).times
    end

    it 'calls shutdown on both existing pools with close block' do
      expect(mock_standard_pool).to receive(:shutdown).and_yield(mock_channel)
      expect(mock_confirms_pool).to receive(:shutdown).and_yield(mock_channel)

      described_class.reset!

      expect(mock_channel).to have_received(:close).twice
    end

    it 'resets creator_pid' do
      described_class.reset!
      expect(described_class.instance_variable_get(:@creator_pid)).to be_nil
    end

    it 'handles reset when only one pool exists' do
      described_class.instance_variable_set(:@standard_pool, nil)
      described_class.instance_variable_set(:@confirms_pool, nil)

      allow(ConnectionPool).to receive(:new).and_return(mock_standard_pool)
      allow(mock_standard_pool).to receive(:with)
      described_class.with_channel(confirms: false) { |_channel| nil }

      expect(mock_standard_pool).to receive(:shutdown).and_yield(mock_channel)

      described_class.reset!

      expect(mock_channel).to have_received(:close)
    end
  end

  describe '.reset_confirms_pool!' do
    before do
      allow(ConnectionPool).to receive(:new).and_return(
        mock_standard_pool,
        mock_confirms_pool,
      )
      allow(mock_standard_pool).to receive(:with)
      allow(mock_confirms_pool).to receive(:with)

      # Create both pools
      described_class.with_channel(confirms: false) { |_channel| nil }
      described_class.with_channel(confirms: true) { |_channel| nil }
    end

    it 'resets only the confirms pool instance variable' do
      described_class.reset_confirms_pool!

      expect(described_class.instance_variable_get(:@standard_pool)).to eq(
        mock_standard_pool,
      )
      expect(described_class.instance_variable_get(:@confirms_pool)).to be_nil
    end

    it 'calls shutdown on confirms pool with close block' do
      expect(mock_confirms_pool).to receive(:shutdown).and_yield(mock_channel)

      described_class.reset_confirms_pool!

      expect(mock_channel).to have_received(:close)
    end

    it 'does not affect standard pool' do
      expect(mock_standard_pool).not_to receive(:shutdown)

      described_class.reset_confirms_pool!
    end

    it 'creates new confirms pool after reset' do
      described_class.reset_confirms_pool!

      new_mock_confirms_pool = instance_double(ConnectionPool, with: nil)
      allow(ConnectionPool).to receive(:new).and_return(new_mock_confirms_pool)

      described_class.with_channel(confirms: true) { |_channel| nil }

      expect(ConnectionPool).to have_received(:new).exactly(3).times
    end

    it 'handles reset when only standard pool exists' do
      described_class.instance_variable_set(:@confirms_pool, nil)

      expect { described_class.reset_confirms_pool! }.not_to raise_error
    end

    it 'handles reset when no pools exist' do
      described_class.instance_variable_set(:@standard_pool, nil)
      described_class.instance_variable_set(:@confirms_pool, nil)

      expect { described_class.reset_confirms_pool! }.not_to raise_error
    end
  end
end
