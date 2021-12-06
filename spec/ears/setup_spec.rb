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
        .with(channel, :topic, 'name', {})
        .and_return(exchange)

      expect(Ears::Setup.new.exchange('name', :topic)).to eq(exchange)
    end

    it 'passes the given options to the exchange' do
      expect(Bunny::Exchange).to receive(:new)
        .with(channel, :topic, 'name', { test: 1 })
        .and_return(exchange)

      expect(Ears::Setup.new.exchange('name', :topic, { test: 1 })).to eq(
        exchange,
      )
    end
  end

  describe '#queue' do
    it 'creates a new bunny queue with the given options' do
      expect(Bunny::Queue).to receive(:new)
        .with(channel, 'name', {})
        .and_return(queue)

      expect(Ears::Setup.new.queue('name')).to eq(queue)
    end

    it 'passes the given options to the queue' do
      expect(Bunny::Queue).to receive(:new)
        .with(channel, 'name', { test: 1 })
        .and_return(queue)

      expect(Ears::Setup.new.queue('name', { test: 1 })).to eq(queue)
    end

    it 'does not pass on options that are processed by ears' do
      expect(Bunny::Queue).to receive(:new)
        .with(
          channel,
          'name',
          {
            test: 1,
            arguments: {
              'x-dead-letter-exchange' => '',
              'x-dead-letter-routing-key' => 'name.retry',
            },
          },
        )
        .and_return(queue)

      expect(
        Ears::Setup.new.queue(
          'name',
          { retry_queue: true, retry_delay: 1000, error_queue: true, test: 1 },
        ),
      ).to eq(queue)
    end

    it 'creates a retry queue with a derived name when option is set' do
      expect(Bunny::Queue).to receive(:new).with(
        channel,
        'name.retry',
        {
          arguments: {
            'x-message-ttl' => 5000,
            'x-dead-letter-exchange' => '',
            'x-dead-letter-routing-key' => 'name',
          },
        },
      )

      expect(Ears::Setup.new.queue('name', retry_queue: true)).to eq(queue)
    end

    it 'adds the retry queue as a deadletter to the original queue' do
      expect(Bunny::Queue).to receive(:new).with(
        channel,
        'name',
        {
          arguments: {
            'x-dead-letter-exchange' => '',
            'x-dead-letter-routing-key' => 'name.retry',
          },
        },
      )

      expect(Ears::Setup.new.queue('name', retry_queue: true)).to eq(queue)
    end

    it 'uses the given retry delay for the retry queue' do
      expect(Bunny::Queue).to receive(:new).with(
        channel,
        'name.retry',
        {
          arguments: {
            'x-message-ttl' => 1000,
            'x-dead-letter-exchange' => '',
            'x-dead-letter-routing-key' => 'name',
          },
        },
      )

      expect(
        Ears::Setup.new.queue('name', retry_queue: true, retry_delay: 1000),
      ).to eq(queue)
    end

    it 'creates an error queue with derived name if option is set' do
      expect(Bunny::Queue).to receive(:new).with(channel, 'name.error', {})

      expect(Ears::Setup.new.queue('name', error_queue: true)).to eq(queue)
    end
  end

  describe '#consumer' do
    let(:consumer_class) { Class.new(Ears::Consumer) }
    let(:consumer_instance) { instance_double(consumer_class) }
    let(:consumer_wrapper) { instance_double(Ears::ConsumerWrapper) }
    let(:delivery_info) { instance_double(Bunny::DeliveryInfo) }
    let(:metadata) { instance_double(Bunny::MessageProperties) }
    let(:payload) { 'my payload' }

    before do
      allow(consumer_class).to receive(:new).and_return(consumer_instance)
      allow(Ears::ConsumerWrapper).to receive(:new).and_return(consumer_wrapper)
      allow(consumer_wrapper).to receive(:on_delivery)
      allow(queue).to receive(:subscribe_with)
      stub_const('MyConsumer', consumer_class)
    end

    it 'instantiates the given class and registers it as a consumer' do
      expect(Ears::ConsumerWrapper).to receive(:new)
        .with(consumer_instance, channel, queue, 'MyConsumer-1', {})
        .and_return(consumer_wrapper)
      expect(consumer_wrapper).to receive(:on_delivery).and_yield(
        delivery_info,
        metadata,
        payload,
      )
      expect(consumer_wrapper).to receive(:process_delivery).with(
        delivery_info,
        metadata,
        payload,
      )
      expect(queue).to receive(:subscribe_with).with(consumer_wrapper)

      Ears::Setup.new.consumer(queue, MyConsumer)
    end

    it 'passes the consumer arguments' do
      expect(Ears::ConsumerWrapper).to receive(:new)
        .with(consumer_instance, channel, queue, 'MyConsumer-1', { a: 1 })
        .and_return(consumer_wrapper)
      expect(consumer_wrapper).to receive(:on_delivery).and_yield(
        delivery_info,
        metadata,
        payload,
      )
      expect(consumer_wrapper).to receive(:process_delivery).with(
        delivery_info,
        metadata,
        payload,
      )
      expect(queue).to receive(:subscribe_with).with(consumer_wrapper)

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
        .with(consumer_wrapper)
        .exactly(3)
        .times

      Ears::Setup.new.consumer(queue, MyConsumer, 3)
    end

    it 'passes the prefetch argument to the channel' do
      expect(channel).to receive(:prefetch).with(5)

      Ears::Setup.new.consumer(
        queue,
        MyConsumer,
        1,
        { prefetch: 5, bla: 'test' },
      )
    end

    it 'numbers the consumers' do
      expect(Ears::ConsumerWrapper).to receive(:new)
        .with(consumer_instance, channel, queue, 'MyConsumer-1', {})
        .and_return(consumer_wrapper)
      expect(Ears::ConsumerWrapper).to receive(:new)
        .with(consumer_instance, channel, queue, 'MyConsumer-2', {})
        .and_return(consumer_wrapper)

      Ears::Setup.new.consumer(queue, MyConsumer, 2)
    end
  end
end
