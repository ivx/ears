require 'ears/configuration'

RSpec.describe Ears::Configuration do
  let(:configuration) { Ears::Configuration.new }

  it 'has a default rabbitmq url' do
    expect(configuration.rabbitmq_url).to eq(
      'amqp://guest:guest@localhost:5672',
    )
  end

  it 'allows setting the rabbitmq url' do
    configuration.rabbitmq_url = 'test'

    expect(configuration.rabbitmq_url).to eq('test')
  end

  it 'allows setting the connection name' do
    configuration.connection_name = 'conn'

    expect(configuration.connection_name).to eq('conn')
  end

  it 'allows setting the recover_from_connection_close' do
    configuration.recover_from_connection_close = false

    expect(configuration.recover_from_connection_close).to be(false)
  end

  it 'allows setting the recovery_attempts' do
    configuration.recovery_attempts = 2

    expect(configuration.recovery_attempts).to eq(2)
  end

  it 'has a default recovery_attempt' do
    expect(configuration.recovery_attempts).to eq(10)
  end

  context 'when recovery attempts are set' do
    before { configuration.recovery_attempts = 2 }

    it 'sets recovery_attempts_exhausted to a raising proc' do
      proc = configuration.recovery_attempts_exhausted

      expect { proc.call }.to raise_error(
        Ears::MaxRecoveryAttemptsExhaustedError,
      )
    end
  end

  context 'when recovery attempts are set to nil' do
    before { configuration.recovery_attempts = nil }

    it 'sets also recovery_attempts_exhausted to nil' do
      expect(configuration.recovery_attempts).to be_nil
    end
  end

  describe 'publisher retry configuration' do
    describe '#publisher_max_retries' do
      it 'has a default value of 3' do
        expect(configuration.publisher_max_retries).to eq(3)
      end

      it 'allows setting the value' do
        configuration.publisher_max_retries = 5
        expect(configuration.publisher_max_retries).to eq(5)
      end
    end

    describe '#publisher_retry_base_delay' do
      it 'has a default value of 0.1' do
        expect(configuration.publisher_retry_base_delay).to eq(0.1)
      end

      it 'allows setting the value' do
        configuration.publisher_retry_base_delay = 1.0
        expect(configuration.publisher_retry_base_delay).to eq(1.0)
      end
    end

    describe '#publisher_retry_backoff_factor' do
      it 'has a default value of 2.0' do
        expect(configuration.publisher_retry_backoff_factor).to eq(2.0)
      end

      it 'allows setting the value' do
        configuration.publisher_retry_backoff_factor = 1.5
        expect(configuration.publisher_retry_backoff_factor).to eq(1.5)
      end
    end
  end

  describe 'publisher pool configuration' do
    describe '#publisher_pool_size' do
      it 'has a default value of 32' do
        expect(configuration.publisher_pool_size).to eq(32)
      end

      it 'allows setting the value' do
        configuration.publisher_pool_size = 16
        expect(configuration.publisher_pool_size).to eq(16)
      end
    end

    describe '#publisher_pool_timeout' do
      it 'has a default value of 2' do
        expect(configuration.publisher_pool_timeout).to eq(2)
      end

      it 'allows setting the value' do
        configuration.publisher_pool_timeout = 5
        expect(configuration.publisher_pool_timeout).to eq(5)
      end
    end
  end

  describe 'publisher connection recovery configuration' do
    describe '#publisher_connection_attempts' do
      it 'has a default value of 30' do
        expect(configuration.publisher_connection_attempts).to eq(30)
      end

      it 'allows setting the value' do
        configuration.publisher_connection_attempts = 10
        expect(configuration.publisher_connection_attempts).to eq(10)
      end
    end

    describe '#publisher_connection_base_delay' do
      it 'has a default value of 1' do
        expect(configuration.publisher_connection_base_delay).to eq(1)
      end

      it 'allows setting the value' do
        configuration.publisher_connection_base_delay = 0.5
        expect(configuration.publisher_connection_base_delay).to eq(0.5)
      end
    end

    describe '#publisher_connection_backoff_factor' do
      it 'has a default value of 1.5' do
        expect(configuration.publisher_connection_backoff_factor).to eq(1.5)
      end

      it 'allows setting the value' do
        configuration.publisher_connection_backoff_factor = 2.0
        expect(configuration.publisher_connection_backoff_factor).to eq(2.0)
      end
    end
  end

  describe '#logger' do
    context 'with default logger' do
      it 'has a default logger' do
        expect(configuration.logger).to be_a(Logger)
      end

      it 'writes to IO::NULL' do
        expect do
          configuration.logger.info('test message')
        end.not_to output.to_stdout
      end

      it 'responds to standard logging methods' do
        logger = configuration.logger

        expect(logger).to respond_to(:debug)
        expect(logger).to respond_to(:info)
        expect(logger).to respond_to(:warn)
        expect(logger).to respond_to(:error)
        expect(logger).to respond_to(:fatal)
      end
    end

    context 'with custom logger' do
      let(:output) { StringIO.new }
      let(:custom_logger) { Logger.new(output) }

      before { configuration.logger = custom_logger }

      it { expect(configuration.logger).to eq(custom_logger) }

      it 'writes to the custom logger output' do
        configuration.logger.info('test message')
        expect(output.string).to include('test message')
      end
    end
  end

  describe '#validate!' do
    it 'returns nil on valid configuration' do
      configuration.connection_name = 'test'
      expect(configuration.validate!).to be_nil
    end

    it 'raises an error if connection name is not set' do
      expect { configuration.validate! }.to raise_error(
        Ears::Configuration::ConnectionNameMissing,
      )
    end
  end
end
