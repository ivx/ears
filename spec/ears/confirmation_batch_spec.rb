require 'ears/confirmation_batch'

RSpec.describe Ears::ConfirmationBatch do
  let(:mock_channel) { instance_double(Bunny::Channel) }
  let(:mock_publisher) { instance_double(Ears::Publisher) }
  let(:mock_config) do
    instance_double(Ears::Configuration, publisher_confirms_batch_size: 100)
  end
  let(:mock_exchange) { instance_double(Bunny::Exchange) }
  let(:default_options) do
    {
      persistent: true,
      timestamp: Time.now.to_i,
      headers: {
      },
      content_type: 'application/json',
    }
  end

  let(:batch) { described_class.new(mock_channel, mock_publisher, mock_config) }

  before do
    allow(mock_publisher).to receive(:send).with(
      :create_exchange,
      mock_channel,
    ).and_return(mock_exchange)
    allow(mock_publisher).to receive(:send).with(
      :default_publish_options,
    ).and_return(default_options)
    allow(mock_exchange).to receive(:publish)
  end

  describe '#initialize' do
    it 'initializes with channel, publisher, and config' do
      expect(batch.instance_variable_get(:@channel)).to eq(mock_channel)
      expect(batch.instance_variable_get(:@publisher)).to eq(mock_publisher)
      expect(batch.instance_variable_get(:@config)).to eq(mock_config)
    end

    it 'initializes message count to zero' do
      expect(batch.instance_variable_get(:@message_count)).to eq(0)
    end
  end

  describe '#publish' do
    let(:data) { { id: 1, name: 'test' } }
    let(:routing_key) { 'test.message' }
    let(:custom_options) { { headers: { 'version' => '2.0' } } }

    it 'creates exchange using publisher' do
      batch.publish(data, routing_key: routing_key)

      expect(mock_publisher).to have_received(:send).with(
        :create_exchange,
        mock_channel,
      )
    end

    it 'gets default publish options from publisher' do
      batch.publish(data, routing_key: routing_key)

      expect(mock_publisher).to have_received(:send).with(
        :default_publish_options,
      )
    end

    it 'publishes message with default options' do
      batch.publish(data, routing_key: routing_key)

      expected_options = { routing_key: routing_key }.merge(default_options)
      expect(mock_exchange).to have_received(:publish).with(
        data,
        expected_options,
      )
    end

    it 'publishes message with custom options merged' do
      batch.publish(data, routing_key: routing_key, **custom_options)

      expected_options = { routing_key: routing_key }.merge(
        default_options.merge(custom_options),
      )
      expect(mock_exchange).to have_received(:publish).with(
        data,
        expected_options,
      )
    end

    it 'increments message count' do
      expect { batch.publish(data, routing_key: routing_key) }.to change {
        batch.instance_variable_get(:@message_count)
      }.from(0).to(1)
    end

    it 'increments message count for multiple messages' do
      batch.publish(data, routing_key: routing_key)
      batch.publish(data, routing_key: routing_key)

      expect(batch.instance_variable_get(:@message_count)).to eq(2)
    end

    context 'when batch size limit is reached' do
      let(:small_limit_config) do
        instance_double(Ears::Configuration, publisher_confirms_batch_size: 2)
      end
      let(:batch) do
        described_class.new(mock_channel, mock_publisher, small_limit_config)
      end

      it 'allows publishing up to the limit' do
        batch.publish(data, routing_key: routing_key)
        batch.publish(data, routing_key: routing_key)

        expect(mock_exchange).to have_received(:publish).twice
      end

      it 'raises BatchSizeExceeded when limit exceeded' do
        batch.publish(data, routing_key: routing_key)
        batch.publish(data, routing_key: routing_key)

        expect { batch.publish(data, routing_key: routing_key) }.to raise_error(
          Ears::BatchSizeExceeded,
          'Batch size limit (2) exceeded',
        )
      end

      it 'does not publish when limit exceeded' do
        batch.publish(data, routing_key: routing_key)
        batch.publish(data, routing_key: routing_key)

        expect { batch.publish(data, routing_key: routing_key) }.to raise_error(
          Ears::BatchSizeExceeded,
        )

        expect(mock_exchange).to have_received(:publish).exactly(2).times
      end

      it 'does not increment count when limit exceeded' do
        batch.publish(data, routing_key: routing_key)
        batch.publish(data, routing_key: routing_key)

        expect { batch.publish(data, routing_key: routing_key) }.to raise_error(
          Ears::BatchSizeExceeded,
        )

        expect(batch.instance_variable_get(:@message_count)).to eq(2)
      end
    end

    context 'with various data types' do
      it 'handles hash data' do
        hash_data = { user_id: 123, action: 'login' }

        expect {
          batch.publish(hash_data, routing_key: routing_key)
        }.not_to raise_error
      end

      it 'handles array data' do
        array_data = [1, 2, 3]

        expect {
          batch.publish(array_data, routing_key: routing_key)
        }.not_to raise_error
      end

      it 'handles string data' do
        string_data = 'test message'

        expect {
          batch.publish(string_data, routing_key: routing_key)
        }.not_to raise_error
      end
    end
  end

  describe '#clear' do
    it 'resets message count to zero' do
      batch.publish({ id: 1 }, routing_key: 'test')
      batch.publish({ id: 2 }, routing_key: 'test')

      expect(batch.instance_variable_get(:@message_count)).to eq(2)

      batch.clear

      expect(batch.instance_variable_get(:@message_count)).to eq(0)
    end

    it 'allows publishing again after clear' do
      small_limit_config =
        instance_double(Ears::Configuration, publisher_confirms_batch_size: 1)
      batch =
        described_class.new(mock_channel, mock_publisher, small_limit_config)

      batch.publish({ id: 1 }, routing_key: 'test')

      expect { batch.publish({ id: 2 }, routing_key: 'test') }.to raise_error(
        Ears::BatchSizeExceeded,
      )

      batch.clear

      expect {
        batch.publish({ id: 3 }, routing_key: 'test')
      }.not_to raise_error
    end
  end
end
