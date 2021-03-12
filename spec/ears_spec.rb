require 'ears'

RSpec.describe Ears do
  let(:bunny) { instance_double(Bunny::Session) }
  let(:channel) { instance_double(Bunny::Channel) }

  before do
    Ears.reset!
    allow(Bunny).to receive(:new).and_return(bunny)
    allow(bunny).to receive(:start)
    allow(bunny).to receive(:create_channel).and_return(channel)
  end

  it 'has a version number' do
    expect(Ears::VERSION).not_to be nil
  end

  describe '.connection' do
    it 'connects when it is accessed' do
      expect(bunny).to receive(:start)

      Ears.connection
    end
  end

  describe '.channel' do
    it 'creates a channel when it is accessed' do
      expect(bunny).to receive(:create_channel).and_return(channel)

      Ears.channel
    end

    it 'stores the channel on the current thread' do
      expect(Ears.channel).to eq(Thread.current[:ears_channel])
    end
  end

  describe '.setup' do
    let(:exchange) { instance_double(Bunny::Exchange) }
    let(:queue) { instance_double(Bunny::Queue) }
    let(:consumer_class) do
      Class.new(Bunny::Consumer) do
        def work(delivery_info, metadata, payload); end
      end
    end
    let(:consumer_instance) { instance_double(consumer_class) }
    let(:delivery_info) { instance_double(Bunny::DeliveryInfo) }
    let(:metadata) { instance_double(Bunny::MessageProperties) }
    let(:payload) { 'my payload' }

    before do
      allow(Bunny::Exchange).to receive(:new).and_return(exchange)
      allow(Bunny::Queue).to receive(:new).and_return(queue)
      allow(queue).to receive(:bind)
      allow(queue).to receive(:subscribe_with)
      allow(consumer_class).to receive(:new).and_return(consumer_instance)
      allow(consumer_instance).to receive(:on_delivery).and_yield(
        delivery_info,
        metadata,
        payload,
      )
      allow(consumer_instance).to receive(:work)
      allow(Thread).to receive(:new).and_yield

      stub_const('MyConsumer', consumer_class)
    end

    it 'creates a given exchange' do
      expect(Bunny::Exchange).to receive(:new).with(
        channel,
        :topic,
        'my-exchange',
      )

      Ears.setup { exchange('my-exchange', :topic) }
    end

    it 'creates a queue' do
      expect(Bunny::Queue).to receive(:new).with(channel, 'my-queue')

      Ears.setup do
        exchange = exchange('my-exchange', :topic)
        queue = queue('my-queue')
      end
    end

    it 'binds a queue to an exchange' do
      expect(queue).to receive(:bind).with(exchange, routing_key: 'test')

      Ears.setup do
        exchange = exchange('my-exchange', :topic)
        queue = queue('my-queue')
        queue.bind(exchange, routing_key: 'test')
      end
    end

    it 'starts a consumer subscribed to a queue' do
      expect(consumer_instance).to receive(:on_delivery)
        .and_yield(delivery_info, metadata, payload)
        .ordered
      expect(consumer_instance).to receive(:work)
        .with(delivery_info, metadata, payload)
        .ordered
      expect(queue).to receive(:subscribe_with)
        .with(consumer_instance, block: true)
        .ordered

      Ears.setup do
        exchange = exchange('my-exchange', :topic)
        queue = queue('my-queue')
        queue.bind(exchange, routing_key: 'test')
        consumer(queue, MyConsumer)
      end
    end

    it 'starts the consumer on a dedicated thread' do
      expect(Thread).to receive(:new).and_yield

      Ears.setup do
        exchange = exchange('my-exchange', :topic)
        queue = queue('my-queue')
        queue.bind(exchange, routing_key: 'test')
        consumer(queue, MyConsumer)
      end
    end
  end
end
