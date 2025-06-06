# frozen_string_literal: true

RSpec.describe Ears::Setup do
  subject(:setup) { Ears::Setup.new }

  let(:ears_channel) { instance_double(Bunny::Channel) }
  let(:prefetch) { 15 }

  before { allow(Ears).to receive(:channel).and_return(ears_channel) }

  # rubocop:disable RSpec/SubjectStub
  describe '#setup_consumers' do
    let(:consumers) do
      [
        class_double(
          Ears::Consumer,
          exchange: 'my-exchange',
          queue: 'my-queue',
          exchange_type: :topic,
          durable_exchange: true,
          queue_options: {
            my_option: true,
            arguments: {
              'x-custom-argument' => 'forwarded',
            },
          },
          routing_keys: ['my_key'],
          threads: threads,
          prefetch: prefetch,
        ),
      ]
    end
    let(:an_exchange) { instance_double(Bunny::Exchange) }
    let(:a_queue) { instance_double(Bunny::Queue, bind: nil) }
    let(:threads) { 10 }

    before do
      allow(setup).to receive_messages(exchange: an_exchange, queue: a_queue)
      allow(setup).to receive(:consumer)
    end

    it 'sets up the consumers accordingly including its queues etc.' do
      setup.setup_consumers(*consumers)

      expect(setup).to have_received(:exchange).with(
        'my-exchange',
        :topic,
        durable: true,
      )
      expect(setup).to have_received(:queue).with(
        'my-queue',
        { my_option: true, arguments: { 'x-custom-argument' => 'forwarded' } },
      )
      expect(a_queue).to have_received(:bind).with(
        an_exchange,
        routing_key: 'my_key',
      )
      expect(setup).to have_received(:consumer).with(
        a_queue,
        consumers[0],
        threads,
        prefetch: prefetch,
      )
    end
  end
  # rubocop:enable RSpec/SubjectStub

  describe '#exchange' do
    it 'creates a new Bunny exchange with the given options' do
      expect(Bunny::Exchange).to receive(:new).with(
        ears_channel,
        :type,
        :name,
        :some_options,
      )

      setup.exchange(:name, :type, :some_options)
    end
  end

  describe '#queue' do
    it 'creates the Bunny queue' do
      expect(Bunny::Queue).to receive(:new).with(
        ears_channel,
        'aName',
        {
          custom_argument: :forwared,
          arguments: {
            'x-custom-argument' => 'forwarded',
          },
        },
      )

      setup.queue(
        'aName',
        custom_argument: :forwared,
        arguments: { 'x-custom-argument' => 'forwarded' }.freeze,
      )
    end

    it 'creates optionally a related retry queue' do
      expect(Bunny::Queue).to receive(:new).with(
        ears_channel,
        'aName',
        {
          custom_argument: :forwared,
          arguments: {
            'x-dead-letter-exchange' => '',
            'x-dead-letter-routing-key' => 'aName.retry',
            'x-custom-argument' => 'forwarded',
          },
        },
      )

      expect(Bunny::Queue).to receive(:new).with(
        ears_channel,
        'aName.retry',
        {
          custom_argument: :forwared,
          arguments: {
            'x-dead-letter-exchange' => '',
            'x-dead-letter-routing-key' => 'aName',
            'x-message-ttl' => 311,
          },
        },
      )

      setup.queue(
        'aName',
        retry_queue: true,
        retry_delay: 311,
        custom_argument: :forwared,
        arguments: { 'x-custom-argument' => 'forwarded' }.freeze,
      )
    end

    it 'creates optionally a related error queue' do
      expect(Bunny::Queue).to receive(:new).with(
        ears_channel,
        'aName',
        {
          custom_argument: :forwared,
          arguments: {
            'x-custom-argument' => 'forwarded',
          },
        },
      )

      expect(Bunny::Queue).to receive(:new).with(
        ears_channel,
        'aName.error',
        {
          custom_argument: :forwared,
          arguments: {
            'x-custom-argument' => 'forwarded',
          },
        },
      )

      setup.queue(
        'aName',
        error_queue: true,
        custom_argument: :forwared,
        arguments: { 'x-custom-argument' => 'forwarded' }.freeze,
      )
    end
  end

  describe '#consumer' do
    let(:ears_connection) do
      instance_double(Bunny::Session, create_channel: consumer_channel)
    end
    let(:arg_queue) do
      instance_double(
        Bunny::Queue,
        name: 'aQueue',
        options: {
          queue: :options,
        },
      )
    end
    let(:consumer_class) do
      instance_double(Class, name: 'SampleConsumer', new: consumer_instance)
    end
    let(:consumer_instance) { instance_double(Object) }
    let(:consumer_queue) do
      instance_double(
        Bunny::Queue,
        name: 'ConsumerQueue',
        channel: consumer_channel,
        subscribe_with: nil,
      )
    end
    let(:consumer_channel) do
      instance_double(
        Bunny::Channel,
        prefetch: prefetch,
        on_uncaught_exception: nil,
        number: 11,
      )
    end

    before do
      allow(Ears).to receive(:connection).and_return(ears_connection)
      allow(Bunny::Queue).to receive(:new).and_return(consumer_queue)
    end

    it 'creates the specified number of channels' do
      expect(ears_connection).to receive(:create_channel)
        .with(nil, 1, true)
        .exactly(3)
        .times

      setup.consumer(arg_queue, consumer_class, 3)
    end

    it 'setups each channel' do
      expect(consumer_channel).to receive(:prefetch).with(15).once
      expect(consumer_channel).to receive(:on_uncaught_exception).once

      setup.consumer(
        arg_queue,
        consumer_class,
        1,
        { prefetch: prefetch, custom: :options },
      )
    end

    it 'creates the specified number of queues' do
      expect(Bunny::Queue).to receive(:new)
        .exactly(4)
        .times
        .with(consumer_channel, arg_queue.name, arg_queue.options)

      setup.consumer(arg_queue, consumer_class, 4)
    end

    it 'setups each created queue' do
      expect(consumer_queue).to receive(:subscribe_with).once

      setup.consumer(arg_queue, consumer_class, 1)
    end

    it 'creates the specified number of consumers' do
      expect(Ears::ConsumerWrapper).to receive(:new)
        .and_call_original
        .exactly(5)
        .times
      expect(consumer_class).to receive(:new).exactly(5).times

      setup.consumer(arg_queue, consumer_class, 5)
    end

    it 'setups the consumer wrappers' do
      expect(Ears::ConsumerWrapper).to receive(:new)
        .with(
          consumer_instance,
          consumer_channel,
          consumer_queue,
          "#{consumer_class.name}-1",
          { custom: :opts },
        )
        .once
        .and_call_original

      setup.consumer(arg_queue, consumer_class, 1, { custom: :opts })
    end
  end
end
