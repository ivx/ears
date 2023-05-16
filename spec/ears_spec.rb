require 'ears'

RSpec.describe Ears do
  let(:bunny) { instance_double(Bunny::Session) }
  let(:channel) { instance_double(Bunny::Channel) }

  before do
    Ears.reset!
    allow(Bunny).to receive(:new).and_return(bunny)
    allow(bunny).to receive(:start)
    allow(bunny).to receive(:create_channel).and_return(channel)
    allow(channel).to receive(:prefetch).with(1)
    allow(channel).to receive(:on_uncaught_exception)
  end

  it 'has a version number' do
    expect(Ears::VERSION).not_to be_nil
  end

  it 'has a configuration' do
    expect(Ears.configuration).to be_a(Ears::Configuration)
  end

  describe '.configure' do
    it 'allows setting the configuration values' do
      Ears.configure do |config|
        config.rabbitmq_url = 'test'
        config.connection_name = 'conn'
      end

      expect(Ears.configuration.rabbitmq_url).to eq('test')
    end

    it 'throws an error if connection name was not set' do
      Ears.reset!

      expect {
        Ears.configure { |config| config.rabbitmq_url = 'test' }
      }.to raise_error(Ears::Configuration::ConnectionNameMissing)
    end
  end

  describe '.connection' do
    let(:rabbitmq_url) { 'amqp://lol:lol@kek.com:15672' }
    let(:connection_name) { 'my connection' }
    let(:recover_from_connection_close) { false }

    before do
      Ears.configure do |config|
        config.rabbitmq_url = rabbitmq_url
        config.connection_name = connection_name
        config.recover_from_connection_close = recover_from_connection_close
      end
    end

    context 'when recover_from_connection_close is set' do
      let(:recover_from_connection_close) { nil }

      it 'connects with config parameters when it is accessed' do
        expect(Bunny).to receive(:new).with(
          rabbitmq_url,
          connection_name: connection_name,
        )
        expect(bunny).to receive(:start)

        Ears.connection
      end
    end

    it 'connects with config parameters when it is accessed' do
      expect(Bunny).to receive(:new).with(
        rabbitmq_url,
        connection_name: connection_name,
        recover_from_connection_close: recover_from_connection_close,
      )
      expect(bunny).to receive(:start)

      Ears.connection
    end
  end

  describe '.channel' do
    it 'creates a channel when it is accessed' do
      expect(bunny).to receive(:create_channel).with(nil, 1, true).and_return(
        channel,
      )
      expect(channel).to receive(:prefetch).with(1)
      expect(channel).to receive(:on_uncaught_exception)

      Ears.channel
    end

    it 'stores the channel on the current thread' do
      expect(Ears.channel).to eq(Thread.current[:ears_channel])
    end
  end

  describe '.setup' do
    let(:exchange) { instance_double(Bunny::Exchange) }
    let(:queue) { instance_double(Bunny::Queue, name: 'queue', options: {}) }
    let(:consumer_wrapper) { instance_double(Ears::ConsumerWrapper) }
    let(:delivery_info) { instance_double(Bunny::DeliveryInfo) }
    let(:metadata) { instance_double(Bunny::MessageProperties) }
    let(:payload) { 'my payload' }

    before do
      allow(Bunny::Exchange).to receive(:new).and_return(exchange)
      allow(Bunny::Queue).to receive(:new).and_return(queue)
      allow(queue).to receive(:bind)
      allow(queue).to receive(:subscribe_with)
      allow(queue).to receive(:channel).and_return(channel)
      allow(Ears::ConsumerWrapper).to receive(:new).and_return(consumer_wrapper)
      allow(consumer_wrapper).to receive(:on_delivery).and_yield(
        delivery_info,
        metadata,
        payload,
      )
      allow(Thread).to receive(:new).and_yield

      stub_const('MyConsumer', Class.new(Ears::Consumer))
    end

    it 'creates a given exchange' do
      expect(Bunny::Exchange).to receive(:new).with(
        channel,
        :topic,
        'my-exchange',
        {},
      )

      Ears.setup { exchange('my-exchange', :topic) }
    end

    it 'creates a queue' do
      expect(Bunny::Queue).to receive(:new).with(channel, 'my-queue', {})

      Ears.setup do
        exchange('my-exchange', :topic)
        queue('my-queue')
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
      expect(consumer_wrapper).to receive(:on_delivery).and_yield(
        delivery_info,
        metadata,
        payload,
      ).ordered
      expect(consumer_wrapper).to receive(:process_delivery).with(
        delivery_info,
        metadata,
        payload,
      ).ordered
      expect(queue).to receive(:subscribe_with).with(consumer_wrapper).ordered

      Ears.setup do
        exchange = exchange('my-exchange', :topic)
        queue = queue('my-queue')
        queue.bind(exchange, routing_key: 'test')
        consumer(queue, MyConsumer)
      end
    end
  end

  describe '.stop!' do
    before { allow(bunny).to receive(:close) }

    it 'stops the connection' do
      Ears.stop!

      expect(bunny).to have_received(:close)
    end

    it 'resets the connection' do
      Ears.connection

      Ears.stop!

      Ears.connection
      Ears.connection

      expect(Bunny).to have_received(:new).twice
    end
  end
end
