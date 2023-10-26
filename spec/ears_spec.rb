# frozen_string_literal: true

RSpec.describe Ears do
  before { Ears.reset! }

  it 'has a version number' do
    expect(Ears::VERSION).to match(/\A[[:digit:]]+\.[[:digit:]]+\.[[:digit:]]+/)
  end

  it 'has a configuration' do
    expect(Ears.configuration).to be_a(Ears::Configuration)
  end

  describe '.configure' do
    it 'allows setting the configuration values' do
      Ears.configure do |config|
        config.rabbitmq_url = 'amqp://guest:guest@test.local:5672'
        config.connection_name = 'conn_name'
        config.recover_from_connection_close = true
        config.recovery_attempts = 666
      end

      expect(Ears.configuration).to have_attributes(
        rabbitmq_url: 'amqp://guest:guest@test.local:5672',
        connection_name: 'conn_name',
        recover_from_connection_close: true,
        recovery_attempts: 666,
      )
    end

    it 'yields the Ears configuration' do
      Ears.configure do |config|
        config.connection_name = 'conn_name'
        expect(config).to be Ears.configuration
      end
    end

    it 'throws an error if connection name was not set' do
      expect do
        Ears.configure { :empty_block }
      end.to raise_error Ears::Configuration::ConnectionNameMissing
    end
  end

  describe '.connection' do
    let(:bunny_session) { instance_double(Bunny::Session, start: nil) }

    context 'with mandatory configuration' do
      before do
        allow(Bunny).to receive(:new).and_return(bunny_session)
        Ears.configure { |config| config.connection_name = 'conn_name' }
        Ears.connection
      end

      it 'connects with config parameters' do
        expect(Bunny).to have_received(:new).with(
          'amqp://guest:guest@localhost:5672',
          connection_name: 'conn_name',
          recovery_attempts: 10,
          recovery_attempts_exhausted: anything,
        )
      end

      it 'starts the connection' do
        expect(bunny_session).to have_received(:start)
      end
    end

    context 'with custom configration' do
      before do
        allow(Bunny).to receive(:new).and_return(bunny_session)
        Ears.configure do |config|
          config.rabbitmq_url = 'amqp://user:password@rabbitmq:15672'
          config.connection_name = 'conn_name'
          config.recover_from_connection_close = false
          config.recovery_attempts = 9
        end
        Ears.connection
      end

      it 'connects with config parameters' do
        expect(Bunny).to have_received(:new).with(
          'amqp://user:password@rabbitmq:15672',
          connection_name: 'conn_name',
          recover_from_connection_close: false,
          recovery_attempts: 9,
          recovery_attempts_exhausted: anything,
        )
      end

      it 'starts the connection' do
        expect(bunny_session).to have_received(:start)
      end
    end
  end

  describe '.channel' do
    let(:bunny_session) do
      instance_double(Bunny::Session, start: nil, create_channel: bunny_channel)
    end

    let(:bunny_channel) do
      instance_double(Bunny::Channel, prefetch: nil, on_uncaught_exception: nil)
    end

    before do
      allow(Bunny).to receive(:new).and_return(bunny_session)
      Ears.channel
    end

    it 'creates a channel when it is accessed' do
      expect(bunny_session).to have_received(:create_channel).with(nil, 1, true)
    end

    it 'configures the channel prefetch' do
      expect(bunny_channel).to have_received(:prefetch).with(1)
    end

    it 'configures the channel exception handler' do
      expect(bunny_channel).to have_received(:on_uncaught_exception)
    end

    it 'stores the channel on the current thread' do
      expect(Ears.channel).to eq(Thread.current[:ears_channel])
    end
  end

  describe '.setup' do
    it 'creates a setup helper and executed the given block on this instance' do
      instance = :none
      Ears.setup { instance = self }
      expect(instance).to be_a Ears::Setup
    end
  end

  describe '.setup_consumers' do
    let(:klasses) { %i[first_class second_class] }

    it 'calls the setup_consumers' do
      setup = instance_double(Ears::Setup, setup_consumers: nil)
      allow(Ears::Setup).to receive(:new).and_return(setup)
      described_class.setup_consumers(*klasses)
      expect(setup).to have_received(:setup_consumers).with(*klasses)
    end
  end

  describe '.stop!' do
    let(:bunny_session) do
      instance_double(
        Bunny::Session,
        start: nil,
        create_channel: bunny_channel,
        close: nil,
      )
    end

    let(:bunny_channel) do
      instance_double(Bunny::Channel, prefetch: nil, on_uncaught_exception: nil)
    end

    before do
      allow(Bunny).to receive(:new).and_return(bunny_session)
      Ears.channel
      Ears.stop!
    end

    it 'stops the connection' do
      expect(bunny_session).to have_received(:close)
    end

    it 'forces to create a new connection afterwards' do
      Ears.connection
      expect(Bunny).to have_received(:new).twice
    end

    it 'forces to create a new channel afterwards' do
      Ears.channel
      expect(bunny_session).to have_received(:create_channel).twice
    end
  end
end
