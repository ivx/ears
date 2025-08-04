require 'ears/publisher'

RSpec.describe Ears::Publisher do
  let(:exchange_name) { 'test_exchange' }
  let(:exchange_type) { :topic }
  let(:exchange_options) { { durable: true } }
  let(:publisher) do
    described_class.new(exchange_name, exchange_type, exchange_options)
  end

  let(:mock_channel) { instance_double(Bunny::Channel) }
  let(:mock_exchange) { instance_double(Bunny::Exchange) }
  let(:routing_key) { 'test.message' }
  let(:message) { 'test message' }

  before do
    allow(Ears).to receive(:channel).and_return(mock_channel)
    allow(Bunny::Exchange).to receive(:new).with(
      mock_channel,
      exchange_type,
      exchange_name,
      { durable: true },
    ).and_return(mock_exchange)
  end

  describe '#publish' do
    let(:data) { { id: 1, name: 'test' } }
    let(:json_string) { '{"id":1,"name":"test"}' }

    before do
      allow(mock_exchange).to receive(:publish)
      allow(MultiJson).to receive(:dump).with(data).and_return(json_string)
    end

    it 'serializes data to JSON and publishes' do
      publisher.publish(data, routing_key: routing_key)

      expected_options = {
        routing_key: routing_key,
        persistent: true,
        timestamp: kind_of(Integer),
        headers: {
        },
        content_type: 'application/json',
      }
      expect(mock_exchange).to have_received(:publish).with(
        json_string,
        expected_options,
      )
    end

    it 'allows overriding JSON options' do
      custom_headers = { 'version' => '2.0' }

      publisher.publish(data, routing_key: routing_key, headers: custom_headers)

      expected_options = {
        routing_key: routing_key,
        persistent: true,
        timestamp: kind_of(Integer),
        headers: custom_headers,
        content_type: 'application/json',
      }
      expect(mock_exchange).to have_received(:publish).with(
        json_string,
        expected_options,
      )
    end

    context 'when an error occurs during publishing' do
      let(:error) { StandardError.new('Publish failed') }

      before { allow(mock_exchange).to receive(:publish).and_raise(error) }

      it 'raises a PublishError' do
        expect {
          publisher.publish(data, routing_key: routing_key)
        }.to raise_error(
          Ears::Publisher::PublishError,
          /test_exchange.*test.message.*#{error.message}/,
        )
      end
    end
  end

  describe '#reset!' do
    before do
      allow(mock_exchange).to receive(:publish)

      publisher.publish('test', routing_key:)
    end

    it 'resets the exchange instance' do
      expect { publisher.reset! }.to change {
        publisher.instance_variable_get(:@exchange)
      }.to(nil)
    end

    it 'creates new exchange after reset' do
      publisher.reset!

      publisher.publish('test', routing_key:)

      expect(Bunny::Exchange).to have_received(:new).twice
    end
  end
end
