require 'ears'
require 'ears/setup'

RSpec.describe Ears::Setup do
  let(:connection) { instance_double(Bunny::Session) }
  let(:channel) { instance_double(Bunny::Channel, number: 1) }
  let(:exchange) { instance_double(Bunny::Exchange) }
  let(:queue) { instance_double(Bunny::Queue, name: 'queue', options: {}) }

  before do
    allow(Ears).to receive(:connection).and_return(connection)
    allow(connection).to receive(:create_channel).and_return(channel)
    allow(Ears).to receive(:channel).and_return(channel)
    allow(channel).to receive(:prefetch)
    allow(channel).to receive(:on_uncaught_exception)
    allow(Bunny::Queue).to receive(:new).and_return(queue)
    allow(queue).to receive(:channel).and_return(channel)
  end

  describe '#exchange' do
    it 'creates a new bunny exchange with the given options' do
      expect(Bunny::Exchange).to receive(:new)
        .with(channel, :topic, 'name')
        .and_return(exchange)

      expect(Ears::Setup.new.exchange('name', :topic)).to eq(exchange)
    end
  end

  describe '#queue' do
    it 'creates a new bunny queue with the given options' do
      expect(Bunny::Queue).to receive(:new)
        .with(channel, 'name')
        .and_return(queue)

      expect(Ears::Setup.new.queue('name')).to eq(queue)
    end
  end

  describe '#consumer' do
    let(:consumer_class) { Class.new(Ears::Consumer) }
    let(:consumer_instance) { instance_double(consumer_class) }
    let(:delivery_info) { instance_double(Bunny::DeliveryInfo) }
    let(:metadata) { instance_double(Bunny::MessageProperties) }
    let(:payload) { 'my payload' }

    before do
      allow(consumer_class).to receive(:new).and_return(consumer_instance)
      allow(consumer_instance).to receive(:on_delivery)
      allow(queue).to receive(:subscribe_with)
      stub_const('MyConsumer', consumer_class)
    end

    it 'instantiates the given class and registers it as a consumer' do
      expect(consumer_class).to receive(:new)
        .with(channel, queue, 'MyConsumer-1', false, false, {})
        .and_return(consumer_instance)
      expect(consumer_instance).to receive(:on_delivery).and_yield(
        delivery_info,
        metadata,
        payload,
      )
      expect(consumer_instance).to receive(:process_delivery).with(
        delivery_info,
        metadata,
        payload,
      )
      expect(queue).to receive(:subscribe_with).with(consumer_instance)

      Ears::Setup.new.consumer(queue, MyConsumer)
    end

    it 'passes the consumer arguments' do
      expect(consumer_class).to receive(:new)
        .with(channel, queue, 'MyConsumer-1', false, false, { a: 1 })
        .and_return(consumer_instance)
      expect(consumer_instance).to receive(:on_delivery).and_yield(
        delivery_info,
        metadata,
        payload,
      )
      expect(consumer_instance).to receive(:process_delivery).with(
        delivery_info,
        metadata,
        payload,
      )
      expect(queue).to receive(:subscribe_with).with(consumer_instance)

      Ears::Setup.new.consumer(queue, MyConsumer, 1, { a: 1 })
    end

    it 'creates a dedicated channel and queue for each consumer' do
      expect(connection).to receive(:create_channel)
        .with(nil, 1, true)
        .and_return(channel)
        .exactly(3)
        .times
      expect(channel).to receive(:prefetch).with(1).exactly(3).times
      expect(channel).to receive(:on_uncaught_exception).exactly(3).times
      expect(Bunny::Queue).to receive(:new)
        .with(channel, 'queue', {})
        .and_return(queue)
        .exactly(3)
        .times
      expect(queue).to receive(:subscribe_with)
        .with(consumer_instance)
        .exactly(3)
        .times

      Ears::Setup.new.consumer(queue, MyConsumer, 3)
    end

    it 'numbers the consumers' do
      expect(consumer_class).to receive(:new)
        .with(channel, queue, 'MyConsumer-1', false, false, {})
        .and_return(consumer_instance)
      expect(consumer_class).to receive(:new)
        .with(channel, queue, 'MyConsumer-2', false, false, {})
        .and_return(consumer_instance)

      Ears::Setup.new.consumer(queue, MyConsumer, 2)
    end
  end
end
