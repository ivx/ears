require 'ears/publisher'

RSpec.describe Ears::Publisher do
  let(:exchange_name) { 'test_exchange' }
  let(:exchange_type) { :topic }
  let(:exchange_options) { { durable: true } }
  let(:publisher) do
    described_class.new(exchange_name, exchange_type, exchange_options)
  end

  let(:mock_channel) { instance_double(Bunny::Channel) }
  let(:mock_confirms_channel) do
    instance_double(
      Bunny::Channel,
      wait_for_confirms: true,
      nacked_set: Set.new,
    )
  end
  let(:mock_exchange) { instance_double(Bunny::Exchange) }
  let(:routing_key) { 'test.message' }
  let(:message) { 'test message' }
  let(:config) { Ears.configuration }

  before do
    mock_connection = instance_double(Bunny::Session)
    allow(mock_connection).to receive(:open?).and_return(true)
    allow(Ears).to receive(:connection).and_return(mock_connection)

    allow(Ears::PublisherChannelPool).to receive(:with_channel).with(
      confirms: false,
    ).and_yield(mock_channel)
    allow(Ears::PublisherChannelPool).to receive(:with_channel).with(
      confirms: true,
    ).and_yield(mock_confirms_channel)

    allow(Bunny::Exchange).to receive(:new).and_return(mock_exchange)
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
    let(:retry_handler) { Ears::PublisherRetryHandler.new(config, logger) }
    let(:logger) { Logger.new(IO::NULL) }

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
        logger: logger,
      )
      allow(Ears::PublisherChannelPool).to receive(:reset!)
      allow(retry_handler).to receive(:sleep)
      allow(Ears::PublisherRetryHandler).to receive(:new).and_return(
        retry_handler,
      )
    end

    context 'when publish succeeds on first attempt' do
      before { allow(connection).to receive(:open?).and_return(true) }

      it 'publishes without retrying' do
        publisher.publish(data, routing_key: routing_key)

        expect(mock_exchange).to have_received(:publish).once
        expect(Ears::PublisherChannelPool).not_to have_received(:reset!)
        expect(retry_handler).not_to have_received(:sleep)
      end
    end

    context 'when connection is closed on first attempt (proactive check)' do
      before do
        # Connection is closed initially, then recovers after one retry attempt
        allow(connection).to receive(:open?).and_return(false, false, true)
        allow(Ears::PublisherChannelPool).to receive(:reset!)
      end

      it 'triggers retry mechanism' do
        publisher.publish(data, routing_key: routing_key)

        expect(retry_handler).to have_received(:sleep).once.with(0.1)
        expect(Ears::PublisherChannelPool).to have_received(:reset!).once
      end

      it 'successfully publishes after connection recovers' do
        publisher.publish(data, routing_key: routing_key)

        expect(mock_exchange).to have_received(:publish).once
      end
    end

    context 'when connection is permanently closed' do
      before { allow(connection).to receive(:open?).and_return(false) }

      it 'never attempts to publish' do
        expect {
          publisher.publish(data, routing_key: routing_key)
        }.to raise_error(
          Ears::PublisherRetryHandler::PublishToStaleChannelError,
        )

        expect(Ears::PublisherChannelPool).not_to have_received(:with_channel)
      end
    end

    context 'when connection immediately recovers after failed publish' do
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

      it 'does not delay the second attempt' do
        publisher.publish(data, routing_key: routing_key)
        expect(retry_handler).not_to have_received(:sleep)
      end
    end

    context 'when connection takes time to recover' do
      before do
        allow(connection).to receive(:open?).and_return(
          true,
          false,
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
        expect(retry_handler).to have_received(:sleep).exactly(3).times
      end

      it 'uses exponential backoff for connection delays' do
        publisher.publish(data, routing_key: routing_key)
        expect(retry_handler).to have_received(:sleep).with(0.1).ordered
        expect(retry_handler).to have_received(:sleep).with(0.2).ordered
        expect(retry_handler).to have_received(:sleep).with(0.4).ordered
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
          Ears::PublisherRetryHandler::PublishToStaleChannelError,
          'Connection is not open',
        )
      end

      it 'attempts to reconnect configured number of times' do
        expect {
          publisher.publish(data, routing_key: routing_key)
        }.to raise_error(
          Ears::PublisherRetryHandler::PublishToStaleChannelError,
        )

        expect(retry_handler).to have_received(:sleep).exactly(3).times
      end

      it 'uses exponential backoff until exhausted' do
        expect {
          publisher.publish(data, routing_key: routing_key)
        }.to raise_error(
          Ears::PublisherRetryHandler::PublishToStaleChannelError,
        )

        expect(retry_handler).to have_received(:sleep).with(0.1).ordered
        expect(retry_handler).to have_received(:sleep).with(0.2).ordered
        expect(retry_handler).to have_received(:sleep).with(0.4).ordered
      end

      it 'does not reset channel pool when connection never recovers' do
        expect {
          publisher.publish(data, routing_key: routing_key)
        }.to raise_error(
          Ears::PublisherRetryHandler::PublishToStaleChannelError,
        )

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
        }.to raise_error(
          Ears::PublisherRetryHandler::PublishToStaleChannelError,
        )

        expect(retry_handler).to have_received(:sleep).with(0.5).ordered
        expect(retry_handler).to have_received(:sleep).with(1.5).ordered
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

        expect(mock_exchange).to have_received(:publish).exactly(4).times
        expect(Ears::PublisherChannelPool).not_to have_received(:reset!)
        expect(retry_handler).to have_received(:sleep).twice
      end
    end
  end

  describe '#publish_with_confirmation' do
    let(:data) { { id: 1, name: 'test' } }
    let(:timeout) { 10.0 }

    before do
      allow(mock_exchange).to receive(:publish)
      allow(Timeout).to receive(:timeout).and_yield
    end

    it 'uses confirms channel pool' do
      publisher.publish_with_confirmation(data, routing_key: routing_key)

      expect(Ears::PublisherChannelPool).to have_received(:with_channel).with(
        confirms: true,
      )
    end

    it 'publishes message with correct options' do
      publisher.publish_with_confirmation(data, routing_key: routing_key)

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

    it 'waits for confirmation with default timeout' do
      allow(config).to receive(:publisher_confirms_timeout).and_return(5.0)
      allow(Timeout).to receive(:timeout).with(5.0).and_yield

      publisher.publish_with_confirmation(data, routing_key: routing_key)

      expect(Timeout).to have_received(:timeout).with(5.0)
      expect(mock_confirms_channel).to have_received(:wait_for_confirms)
    end

    it 'waits for confirmation with custom timeout' do
      allow(Timeout).to receive(:timeout).with(timeout).and_yield

      publisher.publish_with_confirmation(
        data,
        routing_key: routing_key,
        timeout: timeout,
      )

      expect(Timeout).to have_received(:timeout).with(timeout)
      expect(mock_confirms_channel).to have_received(:wait_for_confirms)
    end

    it 'returns successfully when confirmed' do
      expect {
        publisher.publish_with_confirmation(data, routing_key: routing_key)
      }.not_to raise_error
    end

    context 'when confirmation times out' do
      before do
        allow(Timeout).to receive(:timeout).and_raise(Timeout::Error)
        allow(mock_confirms_channel).to receive(:nacked_set).and_return(Set.new)
      end

      it 'raises PublishConfirmationTimeout' do
        expect {
          publisher.publish_with_confirmation(
            data,
            routing_key: routing_key,
            timeout: timeout,
          )
        }.to raise_error(
          Ears::PublishConfirmationTimeout,
          "Confirmation timeout after #{timeout}s",
        )
      end
    end

    context 'when message is nacked' do
      before do
        allow(Timeout).to receive(:timeout).and_yield
        allow(mock_confirms_channel).to receive_messages(
          wait_for_confirms: false,
          nacked_set: Set.new([1]),
        )
      end

      it 'raises PublishNacked' do
        expect {
          publisher.publish_with_confirmation(data, routing_key: routing_key)
        }.to raise_error(Ears::PublishNacked, 'Message was nacked by broker')
      end
    end
  end

  describe '#with_confirmation_batch' do
    let(:messages) { [{ id: 1 }, { id: 2 }, { id: 3 }] }

    before do
      allow(mock_exchange).to receive(:publish)
      allow(config).to receive(:publisher_confirms_batch_size).and_return(100)
      allow(Timeout).to receive(:timeout).and_yield
    end

    it 'uses confirms channel pool' do
      publisher.with_confirmation_batch do |batch|
        # empty batch
      end

      expect(Ears::PublisherChannelPool).to have_received(:with_channel).with(
        confirms: true,
      )
    end

    it 'publishes multiple messages in batch' do
      publisher.with_confirmation_batch do |batch|
        messages.each_with_index do |msg, i|
          batch.publish(msg, routing_key: "test.#{i}")
        end
      end

      expect(mock_exchange).to have_received(:publish).exactly(3).times
    end

    it 'waits for confirmation after batch completion' do
      allow(config).to receive(:publisher_confirms_timeout).and_return(15.0)
      allow(Timeout).to receive(:timeout).with(15.0).and_yield

      publisher.with_confirmation_batch do |batch|
        batch.publish({ id: 1 }, routing_key: 'test.1')
      end

      expect(Timeout).to have_received(:timeout).with(15.0)
      expect(mock_confirms_channel).to have_received(:wait_for_confirms)
    end

    it 'waits for confirmation with custom timeout' do
      timeout = 30.0
      allow(Timeout).to receive(:timeout).with(timeout).and_yield

      publisher.with_confirmation_batch(timeout: timeout) do |batch|
        batch.publish({ id: 1 }, routing_key: 'test.1')
      end

      expect(Timeout).to have_received(:timeout).with(timeout)
      expect(mock_confirms_channel).to have_received(:wait_for_confirms)
    end

    context 'when batch size exceeds limit' do
      before do
        allow(config).to receive(:publisher_confirms_batch_size).and_return(2)
      end

      it 'raises BatchSizeExceeded' do
        expect {
          publisher.with_confirmation_batch do |batch|
            3.times { |i| batch.publish({ id: i }, routing_key: "test.#{i}") }
          end
        }.to raise_error(
          Ears::BatchSizeExceeded,
          'Batch size limit (2) exceeded',
        )
      end
    end

    context 'when confirmation times out' do
      before do
        allow(Timeout).to receive(:timeout).and_raise(Timeout::Error)
        allow(mock_confirms_channel).to receive(:nacked_set).and_return(Set.new)
      end

      it 'raises PublishConfirmationTimeout' do
        timeout = 5.0

        expect {
          publisher.with_confirmation_batch(timeout: timeout) do |batch|
            batch.publish({ id: 1 }, routing_key: 'test.1')
          end
        }.to raise_error(
          Ears::PublishConfirmationTimeout,
          "Confirmation timeout after #{timeout}s",
        )
      end
    end

    context 'when batch has nacked messages' do
      before do
        allow(Timeout).to receive(:timeout).and_yield
        allow(mock_confirms_channel).to receive_messages(
          wait_for_confirms: false,
          nacked_set: Set.new([2]),
        )
      end

      it 'raises PublishNacked' do
        expect {
          publisher.with_confirmation_batch do |batch|
            batch.publish({ id: 1 }, routing_key: 'test.1')
            batch.publish({ id: 2 }, routing_key: 'test.2')
          end
        }.to raise_error(Ears::PublishNacked, 'Message was nacked by broker')
      end
    end
  end
end
