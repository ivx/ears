require 'spec_helper'
require 'ears/testing'
require 'ears/testing/message_capture'

RSpec.describe Ears::Testing::MessageCapture do
  subject(:capture) { described_class.new }

  before do
    allow(Ears::Testing).to receive(:configuration).and_return(
      instance_double(Ears::Testing::Configuration, max_captured_messages: 3),
    )
  end

  describe '#add_message' do
    it 'stores a message with all attributes' do
      message =
        capture.add_message(
          'exchange1',
          { id: 1 },
          'routing.key',
          { persistent: true },
        )

      expect(message).to have_attributes(
        exchange_name: 'exchange1',
        routing_key: 'routing.key',
        data: {
          id: 1,
        },
        options: {
          persistent: true,
        },
        timestamp: be_within(1).of(Time.now),
        thread_id: Thread.current.object_id.to_s,
      )
    end

    it 'stores messages per exchange' do
      capture.add_message('exchange1', 'data1', 'key1')
      capture.add_message('exchange2', 'data2', 'key2')
      capture.add_message('exchange1', 'data3', 'key3')

      expect(capture.messages_for('exchange1')).to have_attributes(size: 2)
      expect(capture.messages_for('exchange2')).to have_attributes(size: 1)
    end

    it 'respects max_captured_messages limit' do
      4.times { |i| capture.add_message('exchange1', "data#{i}", 'key') }

      messages = capture.messages_for('exchange1')
      expect(messages.size).to eq(3)
      expect(messages.first.data).to eq('data1')
      expect(messages.last.data).to eq('data3')
    end

    it 'is thread-safe' do
      threads = []
      mutex = Mutex.new
      results = []

      10.times do |i|
        threads << Thread.new do
          message = capture.add_message('exchange1', "data#{i}", 'key')
          mutex.synchronize { results << message }
        end
      end

      threads.each(&:join)
      expect(results.size).to eq(10)
      expect(results.map(&:data).uniq.size).to eq(10)
    end
  end

  describe '#messages_for' do
    it 'returns messages for specific exchange' do
      capture.add_message('exchange1', 'data1', 'key1')
      capture.add_message('exchange2', 'data2', 'key2')

      messages = capture.messages_for('exchange1')
      expect(messages.size).to eq(1)
      expect(messages.first.data).to eq('data1')
    end

    it 'returns empty array for unknown exchange' do
      expect(capture.messages_for('unknown')).to eq([])
    end

    it 'returns a copy of messages' do
      capture.add_message('exchange1', 'data1', 'key1')
      messages = capture.messages_for('exchange1')
      messages.clear

      expect(capture.messages_for('exchange1').size).to eq(1)
    end
  end

  describe '#all_messages' do
    it 'returns messages from all exchanges' do
      capture.add_message('exchange1', 'data1', 'key1')
      capture.add_message('exchange2', 'data2', 'key2')
      capture.add_message('exchange1', 'data3', 'key3')

      expect(capture.all_messages.size).to eq(3)
      expect(capture.all_messages.map(&:data)).to contain_exactly(
        'data1',
        'data2',
        'data3',
      )
    end
  end

  describe '#clear' do
    it 'removes all messages' do
      capture.add_message('exchange1', 'data1', 'key1')
      capture.add_message('exchange2', 'data2', 'key2')

      capture.clear

      expect(capture.all_messages).to be_empty
      expect(capture.messages_for('exchange1')).to be_empty
      expect(capture.messages_for('exchange2')).to be_empty
    end
  end

  describe '#count' do
    before do
      capture.add_message('exchange1', 'data1', 'key1')
      capture.add_message('exchange2', 'data2', 'key2')
      capture.add_message('exchange1', 'data3', 'key3')
    end

    it 'returns count for specific exchange' do
      expect(capture.count('exchange1')).to eq(2)
      expect(capture.count('exchange2')).to eq(1)
    end

    it 'returns total count when no exchange specified' do
      expect(capture.count).to eq(3)
    end

    it 'returns 0 for unknown exchange' do
      expect(capture.count('unknown')).to eq(0)
    end
  end

  describe '#empty?' do
    it 'returns true when no messages' do
      expect(capture).to be_empty
    end

    it 'returns false when messages exist' do
      capture.add_message('exchange1', 'data', 'key')
      expect(capture).not_to be_empty
    end

    it 'returns true after clearing' do
      capture.add_message('exchange1', 'data', 'key')
      capture.clear
      expect(capture).to be_empty
    end
  end

  describe '#find_messages' do
    before do
      capture.add_message('exchange1', { id: 1 }, 'user.created')
      capture.add_message('exchange1', { id: 2 }, 'user.updated')
      capture.add_message('exchange2', { id: 3 }, 'user.created')
    end

    it 'finds messages by exchange_name' do
      messages = capture.find_messages(exchange_name: 'exchange1')
      expect(messages.map { |m| m.data[:id] }).to contain_exactly(1, 2)
    end

    it 'finds messages by routing_key' do
      messages = capture.find_messages(routing_key: 'user.created')
      expect(messages.map { |m| m.data[:id] }).to contain_exactly(1, 3)
    end

    it 'finds messages by data' do
      messages = capture.find_messages(data: { id: 2 })
      expect(messages.size).to eq(1)
      expect(messages.first.routing_key).to eq('user.updated')
    end

    it 'combines multiple criteria' do
      messages =
        capture.find_messages(
          exchange_name: 'exchange1',
          routing_key: 'user.created',
        )
      expect(messages.size).to eq(1)
      expect(messages.first.data).to eq({ id: 1 })
    end
  end
end
