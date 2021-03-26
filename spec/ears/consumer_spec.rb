require 'ears/consumer'

RSpec.describe Ears::Consumer do
  let(:channel) { instance_double(Bunny::Channel) }
  let(:queue) { instance_double(Bunny::Queue) }
  let(:test_class) { Class.new(Ears::Consumer) }
  let(:instance) { test_class.new(channel, queue) }
  let(:delivery_info) { instance_double(Bunny::DeliveryInfo) }
  let(:metadata) { instance_double(Bunny::MessageProperties) }
  let(:payload) { 'my payload' }

  before do
    allow(channel).to receive(:generate_consumer_tag).and_return('test')
    allow(channel).to receive(:number).and_return(1)
  end

  describe '#work' do
    it 'raises a not implemented error' do
      expect { instance.work(delivery_info, metadata, payload) }.to raise_error(
        NotImplementedError,
      )
    end
  end

  describe '#process_delivery' do
    it 'calls #work' do
      expect(instance).to receive(:work).with(delivery_info, metadata, payload)

      instance.process_delivery(delivery_info, metadata, payload)
    end

    it 'returns the result of #work' do
      allow(instance).to receive(:work).and_return(:moep)

      expect(instance.process_delivery(delivery_info, metadata, payload)).to eq(
        :moep,
      )
    end

    it 'acks the message if #work returns :ack' do
      allow(delivery_info).to receive(:delivery_tag).and_return(1)
      allow(instance).to receive(:work).and_return(:ack)

      expect(channel).to receive(:ack).with(1, false)

      instance.process_delivery(delivery_info, metadata, payload)
    end

    pending 'rejects the message if #work returns :reject' do
      allow(delivery_info).to receive(:delivery_tag).and_return(1)
      allow(instance).to receive(:work).and_return(:reject)

      expect(channel).to receive(:reject).with(1)

      instance.process_delivery(delivery_info, metadata, payload)
    end

    pending 'requeues the message if #work returns :requeue' do
      allow(delivery_info).to receive(:delivery_tag).and_return(1)
      allow(instance).to receive(:work).and_return(:requeue)

      expect(channel).to receive(:reject).with(1, true)

      instance.process_delivery(delivery_info, metadata, payload)
    end
  end

  describe '#ack!' do
    let(:test_class) do
      Class.new(Ears::Consumer) do
        def work
          ack!
        end
      end
    end

    it 'returns :ack when called in #work' do
      expect(instance.work).to eq(:ack)
    end
  end
end
