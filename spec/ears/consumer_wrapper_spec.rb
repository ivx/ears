require 'ears/consumer'
require 'ears/consumer_wrapper'

RSpec.describe Ears::ConsumerWrapper do
  let(:channel) { instance_double(Bunny::Channel) }
  let(:queue) { instance_double(Bunny::Queue) }
  let(:consumer) { instance_double(Ears::Consumer) }
  let(:wrapper) do
    Ears::ConsumerWrapper.new(consumer, channel, queue, 'tag', { test: 1 })
  end
  let(:delivery_info) do
    instance_double(Bunny::DeliveryInfo, delivery_tag: delivery_tag)
  end
  let(:delivery_tag) { 1 }
  let(:metadata) { instance_double(Bunny::MessageProperties) }
  let(:payload) { 'my payload' }

  before do
    allow(channel).to receive(:generate_consumer_tag)
    allow(channel).to receive(:ack)
  end

  it 'sets the channel' do
    expect(wrapper.channel).to eq(channel)
  end

  it 'sets the queue' do
    expect(wrapper.queue).to eq(queue)
  end

  it 'sets the consumer_tag' do
    expect(wrapper.consumer_tag).to eq('tag')
  end

  it 'sets the arguments' do
    expect(wrapper.arguments).to eq({ test: 1 })
  end

  describe '#process_delivery' do
    it 'calls the consumer' do
      expect(consumer).to receive(:process_delivery).with(
        delivery_info,
        metadata,
        payload,
      ).and_return(:ack)

      wrapper.process_delivery(delivery_info, metadata, payload)
    end

    it 'returns the result of the consumer' do
      allow(consumer).to receive(:process_delivery).and_return(:ack)

      expect(wrapper.process_delivery(delivery_info, metadata, payload)).to eq(
        :ack,
      )
    end

    it 'acks the message if #work returns :ack' do
      allow(consumer).to receive(:process_delivery).and_return(:ack)

      expect(channel).to receive(:ack).with(delivery_tag, false)

      wrapper.process_delivery(delivery_info, metadata, payload)
    end

    it 'rejects the message if #work returns :reject' do
      allow(consumer).to receive(:process_delivery).and_return(:reject)

      expect(channel).to receive(:reject).with(delivery_tag)

      wrapper.process_delivery(delivery_info, metadata, payload)
    end

    it 'requeues the message if #work returns :requeue' do
      allow(consumer).to receive(:process_delivery).and_return(:requeue)

      expect(channel).to receive(:reject).with(delivery_tag, true)

      wrapper.process_delivery(delivery_info, metadata, payload)
    end
  end
end
