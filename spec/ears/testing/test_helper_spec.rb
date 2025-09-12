require 'spec_helper'
require 'ears/testing'

RSpec.describe Ears::Testing::TestHelper do
  subject(:helper) { test_class.new }

  let(:test_class) { Class.new { include Ears::Testing::TestHelper } }

  before { Ears::Testing.reset! }

  after { helper.ears_reset! if helper.respond_to?(:ears_reset!) }

  describe '#mock_ears' do
    it 'returns a mock channel' do
      channel = helper.mock_ears('test_exchange')
      expect(channel).to be_an_instance_of(
        RSpec::Mocks::InstanceVerifyingDouble,
      )
    end

    it 'sets up message capture' do
      helper.mock_ears('test_exchange')
      expect(Ears::Testing.message_capture).to be_an_instance_of(
        Ears::Testing::MessageCapture,
      )
    end

    it 'accepts multiple exchange names' do
      channel = helper.mock_ears('exchange1', 'exchange2', 'exchange3')
      expect(channel).not_to be_nil
    end

    it 'stores original connection for cleanup' do
      original_connection = instance_double(Bunny::Session)
      Ears.instance_variable_set(:@connection, original_connection)

      helper.mock_ears('test_exchange')

      expect(helper.instance_variable_get(:@original_connection)).to eq(
        original_connection,
      )
    end
  end

  describe '#published_messages' do
    before do
      helper.mock_ears('exchange1', 'exchange2')
      Ears::Testing.message_capture.add_message('exchange1', 'data1', 'key1')
      Ears::Testing.message_capture.add_message('exchange2', 'data2', 'key2')
      Ears::Testing.message_capture.add_message('exchange1', 'data3', 'key3')
      Ears::Testing.message_capture.add_message('exchange2', 'data4', 'key3')
    end

    it 'returns all messages when no exchange specified' do
      messages = helper.published_messages
      expect(messages.size).to eq(4)
      expect(messages.map(&:data)).to contain_exactly(
        'data1',
        'data2',
        'data3',
        'data4',
      )
    end

    it 'returns messages for specific exchange' do
      messages = helper.published_messages('exchange1')
      expect(messages.size).to eq(2)
      expect(messages.map(&:data)).to contain_exactly('data1', 'data3')
    end

    it 'returns empty array when no messages captured' do
      helper.clear_published_messages
      expect(helper.published_messages).to eq([])
    end

    context 'when routing key is passed' do
      it 'returns messages with specified routing key' do
        messages = helper.published_messages(routing_key: 'key3')
        expect(messages.size).to eq(2)
        expect(messages.map(&:data)).to contain_exactly('data3', 'data4')
      end
    end
  end

  describe '#last_published_message' do
    before do
      helper.mock_ears('exchange1')
      Ears::Testing.message_capture.add_message('exchange1', 'first', 'key1')
      Ears::Testing.message_capture.add_message('exchange1', 'last', 'key2')
    end

    it 'returns the last message for an exchange' do
      message = helper.last_published_message('exchange1')
      expect(message.data).to eq('last')
    end

    it 'returns the last message overall when no exchange specified' do
      Ears::Testing.message_capture.add_message(
        'exchange2',
        'very_last',
        'key3',
      )
      message = helper.last_published_message
      expect(message.data).to eq('very_last')
    end

    it 'returns nil when no messages' do
      helper.clear_published_messages
      expect(helper.last_published_message).to be_nil
    end
  end

  describe '#clear_published_messages' do
    it 'clears all captured messages' do
      helper.mock_ears('exchange1')
      Ears::Testing.message_capture.add_message('exchange1', 'data', 'key')

      helper.clear_published_messages

      expect(helper.published_messages).to be_empty
    end

    it 'handles nil message_capture gracefully' do
      expect { helper.clear_published_messages }.not_to raise_error
    end
  end

  describe '#ears_reset!' do
    let(:original_connection) { instance_double(Bunny::Session) }

    before do
      Ears.instance_variable_set(:@connection, original_connection)
      helper.mock_ears('test_exchange')
      Ears::Testing.message_capture.add_message('test', 'data', 'key')
    end

    it 'clears captured messages' do
      helper.ears_reset!
      expect(Ears::Testing.message_capture).to be_nil
    end

    it 'restores original connection' do
      mock_connection = Ears.instance_variable_get(:@connection)
      expect(mock_connection).not_to eq(original_connection)

      helper.ears_reset!

      expect(Ears.instance_variable_get(:@connection)).to eq(
        original_connection,
      )
    end

    it 'resets PublisherChannelPool if defined' do
      helper.ears_reset!

      expect(Ears::PublisherChannelPool.instance_variable_get(:@pool)).to be_nil
    end
  end
end
