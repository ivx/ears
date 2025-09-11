require 'ears/publisher_confirmation_handler'
require 'ears/publisher_channel_pool'

RSpec.describe Ears::PublisherConfirmationHandler do
  let(:config) do
    instance_double(
      Ears::Configuration,
      publisher_confirms_cleanup_timeout: 1.0,
      publisher_confirms_timeout: 5.0,
    )
  end
  let(:logger) { instance_double(Logger, warn: nil) }
  let(:handler) { described_class.new(config: config, logger: logger) }

  let(:mock_channel) do
    instance_double(
      Bunny::Channel,
      wait_for_confirms: true,
      nacked_set: Set.new,
      open?: true,
      close: nil,
    )
  end
  let(:mock_exchange) { instance_double(Bunny::Exchange, publish: nil) }
  let(:data) { { id: 1, name: 'test' } }
  let(:routing_key) { 'test.message' }
  let(:options) { { persistent: true, content_type: 'application/json' } }

  describe '#publish_with_confirmation' do
    it 'publishes message to exchange with correct parameters' do
      handler.publish_with_confirmation(
        channel: mock_channel,
        exchange: mock_exchange,
        data: data,
        routing_key: routing_key,
        options: options,
      )

      expect(mock_exchange).to have_received(:publish).with(
        data,
        { routing_key: routing_key }.merge(options),
      )
    end

    context 'when timeout is nil' do
      let(:config) do
        instance_double(
          Ears::Configuration,
          publisher_confirms_cleanup_timeout: 1.0,
          publisher_confirms_timeout: nil,
        )
      end

      it 'calls wait_for_confirms directly without timeout' do
        allow(mock_channel).to receive(:wait_for_confirms).and_return(true)

        handler.publish_with_confirmation(
          channel: mock_channel,
          exchange: mock_exchange,
          data: data,
          routing_key: routing_key,
          options: options,
        )

        expect(mock_channel).to have_received(:wait_for_confirms)
      end
    end

    context 'when timeout is provided' do
      it 'uses thread-based timeout mechanism' do
        allow(Thread).to receive(:new).and_call_original

        handler.publish_with_confirmation(
          channel: mock_channel,
          exchange: mock_exchange,
          data: data,
          routing_key: routing_key,
          options: options,
        )

        expect(Thread).to have_received(:new)
      end
    end

    context 'when confirmation succeeds' do
      before do
        allow(mock_channel).to receive(:wait_for_confirms).and_return(true)
      end

      it 'completes without raising an error' do
        expect {
          handler.publish_with_confirmation(
            channel: mock_channel,
            exchange: mock_exchange,
            data: data,
            routing_key: routing_key,
            options: options,
          )
        }.not_to raise_error
      end

      it 'does not close the channel' do
        handler.publish_with_confirmation(
          channel: mock_channel,
          exchange: mock_exchange,
          data: data,
          routing_key: routing_key,
          options: options,
        )

        expect(mock_channel).not_to have_received(:close)
      end

      it 'does not reset the confirms pool' do
        allow(Ears::PublisherChannelPool).to receive(:reset_confirms_pool!)

        handler.publish_with_confirmation(
          channel: mock_channel,
          exchange: mock_exchange,
          data: data,
          routing_key: routing_key,
          options: options,
        )

        expect(Ears::PublisherChannelPool).not_to have_received(
          :reset_confirms_pool!,
        )
      end
    end

    context 'when confirmation times out' do
      before do
        # Mock a thread that times out
        mock_thread = instance_double(Thread)
        allow(Thread).to receive(:new).and_return(mock_thread)
        allow(mock_thread).to receive(:join).with(5.0).and_return(nil) # timeout
        allow(mock_thread).to receive(:join).with(1.0).and_return(true) # cleanup join
        allow(mock_channel).to receive(:close)
        allow(mock_channel).to receive_messages(
          open?: true,
          nacked_set: Set.new,
        )
        allow(Ears::PublisherChannelPool).to receive(:reset_confirms_pool!)
      end

      it 'raises PublishConfirmationTimeout error' do
        expect {
          handler.publish_with_confirmation(
            channel: mock_channel,
            exchange: mock_exchange,
            data: data,
            routing_key: routing_key,
            options: options,
          )
        }.to raise_error(
          Ears::PublishConfirmationTimeout,
          'Confirmation timeout after 5.0s',
        )
      end

      it 'closes the channel' do
        expect {
          handler.publish_with_confirmation(
            channel: mock_channel,
            exchange: mock_exchange,
            data: data,
            routing_key: routing_key,
            options: options,
          )
        }.to raise_error(Ears::PublishConfirmationTimeout)

        expect(mock_channel).to have_received(:close).twice
      end

      it 'resets the confirms pool' do
        expect {
          handler.publish_with_confirmation(
            channel: mock_channel,
            exchange: mock_exchange,
            data: data,
            routing_key: routing_key,
            options: options,
          )
        }.to raise_error(Ears::PublishConfirmationTimeout)

        expect(Ears::PublisherChannelPool).to have_received(
          :reset_confirms_pool!,
        )
      end

      it 'logs timeout warning' do
        expect {
          handler.publish_with_confirmation(
            channel: mock_channel,
            exchange: mock_exchange,
            data: data,
            routing_key: routing_key,
            options: options,
          )
        }.to raise_error(Ears::PublishConfirmationTimeout)

        expect(logger).to have_received(:warn).with(
          'Publisher confirmation failed: timeout after 5.0s.',
        )
      end
    end

    context 'when message is nacked' do
      before do
        allow(mock_channel).to receive_messages(
          wait_for_confirms: false,
          nacked_set: Set.new([1, 2]),
          open?: true,
        )
        allow(mock_channel).to receive(:close)
        allow(Ears::PublisherChannelPool).to receive(:reset_confirms_pool!)
      end

      it 'raises PublishNacked error' do
        expect {
          handler.publish_with_confirmation(
            channel: mock_channel,
            exchange: mock_exchange,
            data: data,
            routing_key: routing_key,
            options: options,
          )
        }.to raise_error(Ears::PublishNacked, 'Message was nacked by broker')
      end

      it 'closes the channel' do
        expect {
          handler.publish_with_confirmation(
            channel: mock_channel,
            exchange: mock_exchange,
            data: data,
            routing_key: routing_key,
            options: options,
          )
        }.to raise_error(Ears::PublishNacked)

        expect(mock_channel).to have_received(:close)
      end

      it 'resets the confirms pool' do
        expect {
          handler.publish_with_confirmation(
            channel: mock_channel,
            exchange: mock_exchange,
            data: data,
            routing_key: routing_key,
            options: options,
          )
        }.to raise_error(Ears::PublishNacked)

        expect(Ears::PublisherChannelPool).to have_received(
          :reset_confirms_pool!,
        )
      end

      it 'logs nack warning' do
        expect {
          handler.publish_with_confirmation(
            channel: mock_channel,
            exchange: mock_exchange,
            data: data,
            routing_key: routing_key,
            options: options,
          )
        }.to raise_error(Ears::PublishNacked)

        expect(logger).to have_received(:warn).with(
          'Publisher confirmation failed: message was nacked by broker.',
        )
      end
    end

    context 'when channel close fails during timeout handling' do
      before do
        # Mock a thread that times out
        mock_thread = instance_double(Thread)
        allow(Thread).to receive(:new).and_return(mock_thread)
        allow(mock_thread).to receive(:join).with(5.0).and_return(nil) # timeout
        allow(mock_thread).to receive(:join).with(1.0).and_return(true) # cleanup join
        allow(mock_channel).to receive(:close).and_raise(
          StandardError,
          'Close failed',
        )
        allow(mock_channel).to receive_messages(
          open?: true,
          nacked_set: Set.new,
        )
        allow(Ears::PublisherChannelPool).to receive(:reset_confirms_pool!)
      end

      it 'logs channel close failure warning' do
        expect {
          handler.publish_with_confirmation(
            channel: mock_channel,
            exchange: mock_exchange,
            data: data,
            routing_key: routing_key,
            options: options,
          )
        }.to raise_error(Ears::PublishConfirmationTimeout)

        expect(logger).to have_received(:warn).with(
          'Failed closing channel on timeout: Close failed',
        )
      end
    end

    context 'when cleanup thread does not stop promptly' do
      before do
        # Mock a thread that times out and cleanup also times out
        mock_thread = instance_double(Thread)
        allow(Thread).to receive(:new).and_return(mock_thread)
        allow(mock_thread).to receive(:join).with(5.0).and_return(nil) # timeout
        allow(mock_thread).to receive(:join).with(1.0).and_return(nil) # cleanup timeout
        allow(mock_channel).to receive(:close)
        allow(mock_channel).to receive_messages(
          open?: true,
          nacked_set: Set.new,
        )
        allow(Ears::PublisherChannelPool).to receive(:reset_confirms_pool!)
      end

      it 'logs cleanup warning' do
        expect {
          handler.publish_with_confirmation(
            channel: mock_channel,
            exchange: mock_exchange,
            data: data,
            routing_key: routing_key,
            options: options,
          )
        }.to raise_error(Ears::PublishConfirmationTimeout)

        expect(logger).to have_received(:warn).with(
          'Confirm waiter did not stop promptly after close',
        )
      end
    end
  end
end
