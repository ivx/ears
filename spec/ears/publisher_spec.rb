require 'ears/publisher'

RSpec.describe Ears::Publisher do
  let(:exchange_name) { 'test_exchange' }
  let(:exchange_type) { :topic }
  let(:exchange_options) { { durable: true } }
  let(:publisher) do
    described_class.new(exchange_name, exchange_type, exchange_options)
  end

  let(:mock_channel) { instance_double(Bunny::Channel) }
  let(:mock_exchange) { instance_double(Bunny::Exchange) }
  let(:routing_key) { 'test.message' }
  let(:message) { 'test message' }

  before do
    mock_connection = instance_double(Bunny::Session)
    allow(mock_connection).to receive(:open?).and_return(true)
    allow(Ears).to receive(:connection).and_return(mock_connection)

    allow(Ears::PublisherChannelPool).to receive(:with_channel).and_yield(
      mock_channel,
    )
    allow(Bunny::Exchange).to receive(:new).with(
      mock_channel,
      exchange_type,
      exchange_name,
      { durable: true },
    ).and_return(mock_exchange)
  end

  describe '#publish' do
    let(:data) { { id: 1, name: 'test' } }

    before { allow(mock_exchange).to receive(:publish) }

    it 'serializes data to JSON and publishes' do
      publisher.publish(data, routing_key: routing_key)

      expected_options = {
        routing_key: routing_key,
        persistent: true,
        timestamp: kind_of(Integer),
        headers: {
        },
        content_type: 'application/json',
      }
      expect(mock_exchange).to have_received(:publish).with(
        data,
        expected_options,
      )
    end

    it 'allows overriding JSON options' do
      custom_headers = { 'version' => '2.0' }

      publisher.publish(data, routing_key: routing_key, headers: custom_headers)

      expected_options = {
        routing_key: routing_key,
        persistent: true,
        timestamp: kind_of(Integer),
        headers: custom_headers,
        content_type: 'application/json',
      }
      expect(mock_exchange).to have_received(:publish).with(
        data,
        expected_options,
      )
    end
  end

  describe '#reset!' do
    before do
      allow(mock_exchange).to receive(:publish)
      allow(Ears::PublisherChannelPool).to receive(:reset!)

      publisher.publish('test', routing_key:)
    end

    it 'resets the channel pool' do
      publisher.reset!

      expect(Ears::PublisherChannelPool).to have_received(:reset!)
    end

    it 'creates new exchange after reset' do
      publisher.reset!

      publisher.publish('test', routing_key:)

      expect(Bunny::Exchange).to have_received(:new).twice
    end
  end

  describe 'connection recovery behavior when connection is closed during publish' do
    let(:data) { { id: 1, name: 'test' } }
    let(:config) { instance_double(Ears::Configuration) }
    let(:connection) { instance_double(Bunny::Session) }

    before do
      allow(mock_exchange).to receive(:publish)
      allow(Ears).to receive_messages(
        configuration: config,
        connection: connection,
      )
      allow(config).to receive_messages(
        publisher_connection_attempts: 3,
        publisher_connection_base_delay: 0.1,
        publisher_connection_backoff_factor: 2.0,
        publisher_max_retries: 3,
        publisher_retry_base_delay: 0.1,
        publisher_retry_backoff_factor: 2.0,
      )
      allow(Ears::PublisherChannelPool).to receive(:reset!)
      allow(publisher).to receive(:sleep)
    end

    context 'when publish succeeds on first attempt' do
      before { allow(connection).to receive(:open?).and_return(true) }

      it 'publishes without retrying' do
        publisher.publish(data, routing_key: routing_key)

        expect(mock_exchange).to have_received(:publish).once
        expect(Ears::PublisherChannelPool).not_to have_received(:reset!)
        expect(publisher).not_to have_received(:sleep)
      end
    end

    context 'when connection is closed on first attempt (proactive check)' do
      before do
        # Connection is closed initially, then recovers after one retry attempt
        allow(connection).to receive(:open?).and_return(
          false,
          false,
          true,
          true,
        )
        allow(Ears::PublisherChannelPool).to receive(:reset!)
      end

      it 'triggers retry mechanism' do
        publisher.publish(data, routing_key: routing_key)

        expect(publisher).to have_received(:sleep).once.with(0.1)
        expect(Ears::PublisherChannelPool).to have_received(:reset!).once
      end

      it 'successfully publishes after connection recovers' do
        publisher.publish(data, routing_key: routing_key)

        expect(mock_exchange).to have_received(:publish).once
      end

      it 'never attempts to publish when connection is closed' do
        allow(connection).to receive(:open?).and_return(false)

        expect {
          publisher.publish(data, routing_key: routing_key)
        }.to raise_error(Ears::Publisher::PublishToStaleChannelError)

        expect(Ears::PublisherChannelPool).not_to have_received(:with_channel)
      end
    end

    context 'when connection recovers immediately' do
      before do
        allow(connection).to receive(:open?).and_return(true)
        call_count = 0
        allow(mock_exchange).to receive(:publish) do
          call_count += 1
          if call_count == 1
            raise Bunny::ConnectionClosedError.new('Connection lost')
          end
          nil
        end
      end

      it 'resets the channel pool' do
        publisher.publish(data, routing_key: routing_key)
        expect(Ears::PublisherChannelPool).to have_received(:reset!).once
      end

      it 'publishes the message on second attempt' do
        publisher.publish(data, routing_key: routing_key)
        expect(mock_exchange).to have_received(:publish).twice
      end

      it 'does not sleep when connection is already open' do
        publisher.publish(data, routing_key: routing_key)
        expect(publisher).not_to have_received(:sleep)
      end
    end

    context 'when connection takes time to recover' do
      before do
        allow(connection).to receive(:open?).and_return(
          true,
          false,
          false,
          true,
        )
        call_count = 0
        allow(mock_exchange).to receive(:publish) do
          call_count += 1
          if call_count == 1
            raise Bunny::ConnectionClosedError.new('Connection lost')
          end
          nil
        end
      end

      it 'waits for connection to recover' do
        publisher.publish(data, routing_key: routing_key)
        expect(publisher).to have_received(:sleep).twice
      end

      it 'uses exponential backoff for connection delays' do
        publisher.publish(data, routing_key: routing_key)
        expect(publisher).to have_received(:sleep).with(0.1).ordered
        expect(publisher).to have_received(:sleep).with(0.2).ordered
      end

      it 'publishes after connection recovers' do
        publisher.publish(data, routing_key: routing_key)
        expect(mock_exchange).to have_received(:publish).twice
      end
    end

    context 'when connection never recovers' do
      before do
        allow(connection).to receive(:open?).and_return(false)
        allow(mock_exchange).to receive(:publish).and_raise(
          Bunny::ConnectionClosedError.new('Connection lost'),
        )
      end

      it 'exhausts connection attempts and raises original error' do
        expect {
          publisher.publish(data, routing_key: routing_key)
        }.to raise_error(
          Ears::Publisher::PublishToStaleChannelError,
          'Connection is not open',
        )
      end

      it 'attempts to reconnect configured number of times' do
        expect {
          publisher.publish(data, routing_key: routing_key)
        }.to raise_error(Ears::Publisher::PublishToStaleChannelError)

        expect(publisher).to have_received(:sleep).exactly(3).times
      end

      it 'uses exponential backoff until exhausted' do
        expect {
          publisher.publish(data, routing_key: routing_key)
        }.to raise_error(Ears::Publisher::PublishToStaleChannelError)

        expect(publisher).to have_received(:sleep).with(0.1).ordered
        expect(publisher).to have_received(:sleep).with(0.2).ordered
        expect(publisher).to have_received(:sleep).with(0.4).ordered
      end

      it 'does not reset channel pool when connection never recovers' do
        expect {
          publisher.publish(data, routing_key: routing_key)
        }.to raise_error(Ears::Publisher::PublishToStaleChannelError)

        expect(Ears::PublisherChannelPool).not_to have_received(:reset!)
      end
    end

    context 'with different connection recovery configuration' do
      before do
        allow(config).to receive_messages(
          publisher_connection_attempts: 2,
          publisher_connection_base_delay: 0.5,
          publisher_connection_backoff_factor: 3.0,
        )
        allow(connection).to receive(:open?).and_return(false)
        allow(mock_exchange).to receive(:publish).and_raise(
          Bunny::ConnectionClosedError.new('Connection lost'),
        )
      end

      it 'respects custom connection configuration values' do
        expect {
          publisher.publish(data, routing_key: routing_key)
        }.to raise_error(Ears::Publisher::PublishToStaleChannelError)

        expect(publisher).to have_received(:sleep).with(0.5).ordered
        expect(publisher).to have_received(:sleep).with(1.5).ordered
      end
    end

    context 'when publish fails with non-connection error' do
      let(:error) { StandardError.new('Invalid data') }

      before do
        allow(connection).to receive(:open?).and_return(true)
        allow(mock_exchange).to receive(:publish).and_raise(error)
      end

      it 'retries according to publisher_max_retries and then raises' do
        expect {
          publisher.publish(data, routing_key: routing_key)
        }.to raise_error(StandardError, 'Invalid data')

        expect(mock_exchange).to have_received(:publish).exactly(3).times
        expect(Ears::PublisherChannelPool).not_to have_received(:reset!)
        expect(publisher).to have_received(:sleep).twice
      end
    end
  end
end
