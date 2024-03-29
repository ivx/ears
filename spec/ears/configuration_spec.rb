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
