require 'ears/setup'

RSpec.describe Ears::Setup do
  let(:channel) { instance_double(Bunny::Channel) }
  let(:exchange) { instance_double(Bunny::Exchange) }
  let(:queue) { instance_double(Bunny::Queue) }

  before do
    allow(Ears).to receive(:channel).and_return(channel)
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
      allow(Thread).to receive(:new).and_yield
      stub_const('MyConsumer', consumer_class)
    end

    it 'instantiates the given class and registers it as a consumer' do
      expect(consumer_class).to receive(:new)
        .with(channel, queue, consumer_class.name, false, false, {})
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
        .with(channel, queue, consumer_class.name, false, false, { a: 1 })
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

      Ears::Setup.new.consumer(queue, MyConsumer, { a: 1 })
    end
  end
end
