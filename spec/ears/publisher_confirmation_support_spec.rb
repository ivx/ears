require 'ears/publisher_confirmation_support'
require 'ears/publisher_channel_pool'

RSpec.describe Ears::PublisherConfirmationSupport do
  let(:test_class) do
    Class.new do
      include Ears::PublisherConfirmationSupport

      def validate_connection!
      end

      def create_exchange(channel)
      end
    end
  end
  let(:test_instance) { test_class.new }
  let(:mock_channel) do
    instance_double(
      Bunny::Channel,
      wait_for_confirms: true,
      nacked_set: Set.new,
    )
  end
  let(:mock_exchange) { instance_double(Bunny::Exchange) }
  let(:data) { { id: 1, name: 'test' } }
  let(:routing_key) { 'test.message' }
  let(:publish_options) do
    { persistent: true, content_type: 'application/json' }
  end

  before do
    allow(test_instance).to receive(:validate_connection!)
    allow(test_instance).to receive(:create_exchange).and_return(mock_exchange)
    allow(mock_exchange).to receive(:publish)
    allow(Ears::PublisherChannelPool).to receive(:with_channel).with(
      confirms: true,
    ).and_yield(mock_channel)
  end

  describe '#publish_with_confirms' do
    let(:timeout) { 5.0 }

    before do
      allow(test_instance).to receive(
        :wait_for_confirms_with_timeout,
      ).and_return(true)
    end

    it 'validates connection before publishing' do
      test_instance.send(
        :publish_with_confirms,
        data: data,
        routing_key: routing_key,
        publish_options: publish_options,
      )

      expect(test_instance).to have_received(:validate_connection!)
    end

    it 'uses confirms channel pool' do
      test_instance.send(
        :publish_with_confirms,
        data: data,
        routing_key: routing_key,
        publish_options: publish_options,
      )

      expect(Ears::PublisherChannelPool).to have_received(:with_channel).with(
        confirms: true,
      )
    end

    it 'creates exchange and publishes message' do
      test_instance.send(
        :publish_with_confirms,
        data: data,
        routing_key: routing_key,
        publish_options: publish_options,
      )

      expect(test_instance).to have_received(:create_exchange).with(
        mock_channel,
      )
      expect(mock_exchange).to have_received(:publish).with(
        data,
        { routing_key: routing_key }.merge(publish_options),
      )
    end

    it 'waits for confirmation with timeout' do
      test_instance.send(
        :publish_with_confirms,
        data: data,
        routing_key: routing_key,
        publish_options: publish_options,
        wait_for_confirm: true,
        timeout: timeout,
      )

      expect(test_instance).to have_received(
        :wait_for_confirms_with_timeout,
      ).with(mock_channel, timeout)
    end

    context 'when confirmation succeeds' do
      before do
        allow(test_instance).to receive(
          :wait_for_confirms_with_timeout,
        ).and_return(true)
      end

      it 'does not handle failure' do
        allow(test_instance).to receive(:handle_confirmation_failure)

        test_instance.send(
          :publish_with_confirms,
          data: data,
          routing_key: routing_key,
          publish_options: publish_options,
          wait_for_confirm: true,
          timeout: timeout,
        )

        expect(test_instance).not_to have_received(:handle_confirmation_failure)
      end
    end

    context 'when confirmation fails' do
      before do
        allow(test_instance).to receive(
          :wait_for_confirms_with_timeout,
        ).and_return(false)
        allow(test_instance).to receive(:handle_confirmation_failure)
      end

      it 'handles confirmation failure' do
        test_instance.send(
          :publish_with_confirms,
          data: data,
          routing_key: routing_key,
          publish_options: publish_options,
          wait_for_confirm: true,
          timeout: timeout,
        )

        expect(test_instance).to have_received(
          :handle_confirmation_failure,
        ).with(mock_channel, timeout)
      end
    end

    context 'when wait_for_confirm is false' do
      it 'does not wait for confirmation' do
        allow(test_instance).to receive(:wait_for_confirms_with_timeout)

        test_instance.send(
          :publish_with_confirms,
          data: data,
          routing_key: routing_key,
          publish_options: publish_options,
          wait_for_confirm: false,
        )

        expect(test_instance).not_to have_received(
          :wait_for_confirms_with_timeout,
        )
      end
    end
  end

  describe '#wait_for_confirms_with_timeout' do
    let(:timeout) { 5.0 }

    before { allow(Timeout).to receive(:timeout).and_yield }

    it 'uses Timeout.timeout with specified timeout' do
      test_instance.send(:wait_for_confirms_with_timeout, mock_channel, timeout)

      expect(Timeout).to have_received(:timeout).with(timeout)
    end

    it 'calls wait_for_confirms on channel' do
      test_instance.send(:wait_for_confirms_with_timeout, mock_channel, timeout)

      expect(mock_channel).to have_received(:wait_for_confirms)
    end

    context 'when channel confirms successfully' do
      before do
        allow(mock_channel).to receive(:wait_for_confirms).and_return(true)
      end

      it 'returns true' do
        result =
          test_instance.send(
            :wait_for_confirms_with_timeout,
            mock_channel,
            timeout,
          )

        expect(result).to be(true)
      end
    end

    context 'when channel confirmation fails' do
      before do
        allow(mock_channel).to receive(:wait_for_confirms).and_return(false)
      end

      it 'returns false' do
        result =
          test_instance.send(
            :wait_for_confirms_with_timeout,
            mock_channel,
            timeout,
          )

        expect(result).to be(false)
      end
    end

    context 'when timeout occurs' do
      before { allow(Timeout).to receive(:timeout).and_raise(Timeout::Error) }

      it 'returns false' do
        result =
          test_instance.send(
            :wait_for_confirms_with_timeout,
            mock_channel,
            timeout,
          )

        expect(result).to be(false)
      end
    end
  end

  describe '#handle_confirmation_failure' do
    let(:timeout) { 5.0 }

    context 'when channel has nacked messages' do
      before do
        allow(mock_channel).to receive_messages(nacked_set: Set.new([1, 2]))
      end

      it 'raises PublishNacked error' do
        expect {
          test_instance.send(
            :handle_confirmation_failure,
            mock_channel,
            timeout,
          )
        }.to raise_error(Ears::PublishNacked, 'Message was nacked by broker')
      end
    end

    context 'when channel has empty nacked set' do
      before { allow(mock_channel).to receive_messages(nacked_set: Set.new) }

      it 'raises PublishConfirmationTimeout error' do
        expect {
          test_instance.send(
            :handle_confirmation_failure,
            mock_channel,
            timeout,
          )
        }.to raise_error(
          Ears::PublishConfirmationTimeout,
          "Confirmation timeout after #{timeout}s",
        )
      end
    end

    context 'when channel has nil nacked set' do
      before { allow(mock_channel).to receive_messages(nacked_set: nil) }

      it 'raises PublishConfirmationTimeout error' do
        expect {
          test_instance.send(
            :handle_confirmation_failure,
            mock_channel,
            timeout,
          )
        }.to raise_error(
          Ears::PublishConfirmationTimeout,
          "Confirmation timeout after #{timeout}s",
        )
      end
    end
  end
end

