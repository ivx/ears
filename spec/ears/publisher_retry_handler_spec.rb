require 'ears/publisher_retry_handler'

RSpec.describe Ears::PublisherRetryHandler do
  let(:config) { instance_double(Ears::Configuration) }
  let(:logger) { instance_double(Logger) }
  let(:handler) { described_class.new(config, logger) }
  let(:mock_connection) { instance_double(Bunny::Session) }

  before do
    allow(Ears).to receive(:connection).and_return(mock_connection)
    allow(Ears::PublisherChannelPool).to receive(:reset!)
    allow(logger).to receive(:info)
    allow(logger).to receive(:warn)
    allow(logger).to receive(:error)
    allow(handler).to receive(:sleep)

    allow(config).to receive_messages(
      publisher_max_retries: 3,
      publisher_connection_attempts: 30,
      publisher_connection_base_delay: 1.0,
      publisher_connection_backoff_factor: 1.5,
      publisher_retry_base_delay: 0.1,
      publisher_retry_backoff_factor: 2.0,
    )
  end

  describe '#run' do
    context 'when block executes successfully' do
      it 'returns the block result without retrying' do
        result = handler.run { 'success' }

        expect(result).to eq('success')
        expect(Ears::PublisherChannelPool).not_to have_received(:reset!)
        expect(handler).not_to have_received(:sleep)
      end

      it 'does not log any retry attempts' do
        handler.run { 'success' }

        expect(logger).not_to have_received(:info)
        expect(logger).not_to have_received(:warn)
      end
    end
  end

  describe 'connection error handling' do
    let(:connection_error) do
      Ears::PublisherRetryHandler::PublishToStaleChannelError.new(
        'Connection closed',
      )
    end

    before { allow(mock_connection).to receive(:open?).and_return(true) }

    context 'when connection error occurs and connection immediately recovers' do
      let(:failing_block) do
        call_count = 0
        -> do
          call_count += 1
          raise connection_error if call_count == 1
          'recovered'
        end
      end

      it 'handles the connection error and retries successfully' do
        result = handler.run(&failing_block)

        expect(result).to eq('recovered')
        expect(Ears::PublisherChannelPool).to have_received(:reset!)
      end

      it 'logs connection recovery' do
        handler.run(&failing_block)

        expect(logger).to have_received(:info).with(
          'Trying to reconnect after connection error',
        )
        expect(logger).to have_received(:info).with(
          'Resetting channel pool after connection recovery',
        )
      end

      it 'does not sleep when connection recovers immediately' do
        handler.run(&failing_block)

        expect(handler).not_to have_received(:sleep)
      end
    end

    context 'when connection takes time to recover' do
      let(:failing_block) do
        call_count = 0
        -> do
          call_count += 1
          raise connection_error if call_count == 1
          'recovered'
        end
      end

      before do
        allow(mock_connection).to receive(:open?).and_return(
          false,
          false,
          false,
          true,
        )
      end

      it 'waits for connection recovery with exponential backoff' do
        handler.run(&failing_block)

        expect(handler).to have_received(:sleep).with(1.0).ordered
        expect(handler).to have_received(:sleep).with(1.5).ordered
        expect(handler).to have_received(:sleep).with(2.25).ordered
      end

      it 'logs each connection attempt' do
        handler.run(&failing_block)

        expect(logger).to have_received(:info).with(
          'Connection still closed, attempt 1',
        )
        expect(logger).to have_received(:info).with(
          'Connection still closed, attempt 2',
        )
        expect(logger).to have_received(:info).with(
          'Connection still closed, attempt 3',
        )
      end

      it 'successfully executes after connection recovery' do
        result = handler.run(&failing_block)

        expect(result).to eq('recovered')
        expect(Ears::PublisherChannelPool).to have_received(:reset!)
      end
    end

    context 'when connection never recovers' do
      let(:failing_block) { -> { raise connection_error } }

      before { allow(mock_connection).to receive(:open?).and_return(false) }

      it 'exhausts connection attempts and raises original error' do
        expect { handler.run(&failing_block) }.to raise_error(connection_error)
      end

      it 'attempts to reconnect configured number of times' do
        expect { handler.run(&failing_block) }.to raise_error(connection_error)

        expect(handler).to have_received(:sleep).exactly(30).times
      end

      it 'logs exhausted attempts' do
        expect { handler.run(&failing_block) }.to raise_error(connection_error)

        expect(logger).to have_received(:error).with(
          'Connection attempts exhausted, giving up',
        )
      end

      it 'does not reset channel pool when connection never recovers' do
        expect { handler.run(&failing_block) }.to raise_error(connection_error)

        expect(Ears::PublisherChannelPool).not_to have_received(:reset!)
      end
    end

    context 'with different connection configurations' do
      before do
        allow(config).to receive_messages(
          publisher_connection_attempts: 2,
          publisher_connection_base_delay: 0.5,
          publisher_connection_backoff_factor: 3.0,
        )
        allow(mock_connection).to receive(:open?).and_return(false)
      end

      it 'respects custom connection configuration' do
        expect { handler.run { raise connection_error } }.to raise_error(
          connection_error,
        )

        expect(handler).to have_received(:sleep).with(0.5).ordered
        expect(handler).to have_received(:sleep).with(1.5).ordered
      end
    end
  end

  describe 'different connection error types' do
    before { allow(mock_connection).to receive(:open?).and_return(true) }

    [
      [
        Ears::PublisherRetryHandler::PublishToStaleChannelError,
        ['Connection problem'],
      ],
      [Bunny::ConnectionClosedError, ['Connection problem']],
      [Bunny::NetworkFailure, ['Connection problem', 'Network issue']],
      [IOError, ['Connection problem']],
    ].each do |error_class, args|
      it "handles #{error_class} as a connection error" do
        error = error_class.new(*args)
        failing_block =
          lambda do
            call_count = 0
            -> do
              call_count += 1
              raise error if call_count == 1
              'recovered'
            end
          end.call

        result = handler.run(&failing_block)
        expect(result).to eq('recovered')
        expect(Ears::PublisherChannelPool).to have_received(:reset!)
      end
    end
  end

  describe 'standard error retry logic' do
    let(:standard_error) { StandardError.new('Generic error') }

    context 'when error occurs within retry limit' do
      let(:failing_block) do
        call_count = 0
        -> do
          call_count += 1
          raise standard_error if call_count <= 2
          'success after retries'
        end
      end

      it 'retries with exponential backoff and succeeds' do
        result = handler.run(&failing_block)

        expect(result).to eq('success after retries')
        expect(handler).to have_received(:sleep).once.with(0.2)
      end

      it 'logs each retry attempt' do
        handler.run(&failing_block)

        expect(logger).to have_received(:info).with(
          'Trying to recover from publish error. Attempt 1: StandardError: Generic error',
        )
        expect(logger).to have_received(:info).with(
          'Trying to recover from publish error. Attempt 2: StandardError: Generic error',
        )
      end

      it 'does not reset channel pool for standard errors' do
        handler.run(&failing_block)

        expect(Ears::PublisherChannelPool).not_to have_received(:reset!)
      end
    end

    context 'when retry limit is exceeded' do
      let(:failing_block) { -> { raise standard_error } }

      it 'exhausts retries and raises the original error' do
        expect { handler.run(&failing_block) }.to raise_error(standard_error)
      end

      it 'attempts configured number of retries plus initial attempt' do
        expect { handler.run(&failing_block) }.to raise_error(standard_error)
        expect(handler).to have_received(:sleep).exactly(2).times
      end

      it 'logs exhaustion warning' do
        expect { handler.run(&failing_block) }.to raise_error(standard_error)

        expect(logger).to have_received(:warn).with(
          'Connection attempts exhausted, giving up: StandardError: Generic error',
        )
      end
    end

    context 'with custom retry configuration' do
      before do
        allow(config).to receive_messages(
          publisher_max_retries: 1,
          publisher_retry_base_delay: 0.5,
          publisher_retry_backoff_factor: 3.0,
        )
      end

      it 'respects custom retry configuration' do
        expect { handler.run { raise standard_error } }.to raise_error(
          standard_error,
        )
        expect(handler).not_to have_received(:sleep)
      end
    end
  end

  describe 'integration scenarios' do
    context 'when both connection and standard errors occur' do
      let(:connection_error) do
        Bunny::ConnectionClosedError.new('Network lost')
      end
      let(:standard_error) { ArgumentError.new('Invalid argument') }
      let(:complex_block) do
        call_count = 0
        -> do
          call_count += 1
          case call_count
          when 1
            raise connection_error
          when 2
            raise standard_error
          else
            'finally success'
          end
        end
      end

      before { allow(mock_connection).to receive(:open?).and_return(true) }

      it 'retries both connection and standard errors and eventually succeeds' do
        result = handler.run(&complex_block)

        expect(result).to eq('finally success')
        expect(Ears::PublisherChannelPool).to have_received(:reset!).once
        expect(handler).to have_received(:sleep).once
      end
    end
  end
end
