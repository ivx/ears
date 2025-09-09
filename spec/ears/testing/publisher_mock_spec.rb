require 'spec_helper'
require 'ears/testing'
require 'ears/publisher_channel_pool'

RSpec.describe Ears::Testing::PublisherMock do
  subject(:publisher_mock) do
    described_class.new(exchange_names, message_capture)
  end

  let(:message_capture) { Ears::Testing::MessageCapture.new }
  let(:exchange_names) { ['test_exchange'] }

  before do
    allow(Ears::Testing).to receive(:configuration).and_return(
      instance_double(
        Ears::Testing::Configuration,
        strict_exchange_mocking: true,
        max_captured_messages: 100,
      ),
    )
  end

  describe '#setup_mocks' do
    it 'returns a mock channel' do
      channel = publisher_mock.setup_mocks
      expect(channel).to respond_to(:basic_publish)
      expect(channel).to respond_to(:exchange_declare)
    end

    it 'sets up a mock connection on Ears' do
      publisher_mock.setup_mocks
      connection = Ears.instance_variable_get(:@connection)
      expect(connection).to respond_to(:open?)
      expect(connection.open?).to be true
    end

    it 'mocks PublisherChannelPool.with_channel' do
      expect(Ears::PublisherChannelPool).to receive(:with_channel)
      publisher_mock.setup_mocks
      Ears::PublisherChannelPool.with_channel { |_channel| 'block executed' }
    end

    context 'with multiple exchanges' do
      let(:exchange_names) { %w[exchange1 exchange2 exchange3] }

      it 'sets up mocks for all exchanges' do
        channel = publisher_mock.setup_mocks

        exchange_names.each do |exchange_name|
          expect(channel).to receive(:basic_publish).with(
            'test_data',
            exchange_name,
            'test.key',
            hash_including(:persistent, :content_type),
          )
        end

        exchange_names.each do |exchange_name|
          channel.basic_publish(
            'test_data',
            exchange_name,
            'test.key',
            { persistent: true, content_type: 'application/json' },
          )
        end
      end
    end
  end

  describe 'message capturing' do
    let(:channel) { publisher_mock.setup_mocks }

    it 'captures published messages' do
      channel.basic_publish(
        '{"id": 1}',
        'test_exchange',
        'test.routing.key',
        { persistent: true, content_type: 'application/json' },
      )

      messages = message_capture.messages_for('test_exchange')
      expect(messages.size).to eq(1)
      expect(messages.first).to have_attributes(
        exchange_name: 'test_exchange',
        routing_key: 'test.routing.key',
        data: '{"id": 1}',
        options:
          hash_including(persistent: true, content_type: 'application/json'),
      )
    end

    it 'captures multiple messages' do
      3.times do |i|
        channel.basic_publish(
          "data_#{i}",
          'test_exchange',
          "key_#{i}",
          { persistent: true, content_type: 'application/json' },
        )
      end

      messages = message_capture.messages_for('test_exchange')
      expect(messages.size).to eq(3)
      expect(messages.map(&:data)).to eq(%w[data_0 data_1 data_2])
    end
  end

  describe 'exchange declaration' do
    let(:channel) { publisher_mock.setup_mocks }

    it 'allows exchange declaration' do
      expect {
        channel.exchange_declare('test_exchange', :topic, durable: true)
      }.not_to raise_error
    end

    it 'returns a mock exchange' do
      exchange =
        channel.exchange_declare('test_exchange', :topic, durable: true)
      expect(exchange).to respond_to(:publish)
      expect(exchange.name).to eq('test_exchange')
      expect(exchange.type).to eq(:topic)
    end

    it 'allows publishing through declared exchange' do
      exchange =
        channel.exchange_declare('test_exchange', :topic, durable: true)

      exchange.publish('test_data', routing_key: 'test.key')

      messages = message_capture.messages_for('test_exchange')
      expect(messages.size).to eq(1)
      expect(messages.first.data).to eq('test_data')
    end
  end

  describe 'strict exchange mocking' do
    let(:channel) { publisher_mock.setup_mocks }

    context 'when strict_exchange_mocking is true' do
      it 'raises error for unmocked exchange' do
        expect {
          channel.basic_publish('data', 'unmocked_exchange', 'key', {})
        }.to raise_error(
          Ears::Testing::UnmockedExchangeError,
          "Exchange 'unmocked_exchange' has not been mocked. Add mock_ears('unmocked_exchange') to your test setup.",
        )
      end
    end

    context 'when strict_exchange_mocking is false' do
      before do
        allow(Ears::Testing.configuration).to receive(
          :strict_exchange_mocking,
        ).and_return(false)
      end

      it 'does not raise error for unmocked exchange' do
        expect {
          channel.basic_publish('data', 'unmocked_exchange', 'key', {})
        }.not_to raise_error
      end

      it 'does not capture messages for unmocked exchange' do
        channel.basic_publish('data', 'unmocked_exchange', 'key', {})
        expect(message_capture.messages_for('unmocked_exchange')).to be_empty
      end
    end
  end

  describe 'register_exchange support' do
    let(:channel) { publisher_mock.setup_mocks }

    it 'allows register_exchange calls' do
      exchange = instance_double(Bunny::Exchange, name: 'test_exchange')
      expect { channel.register_exchange(exchange) }.not_to raise_error
    end
  end
end
