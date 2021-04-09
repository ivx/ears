require 'ears/consumer'

RSpec.describe Ears::Consumer do
  let(:channel) { instance_double(Bunny::Channel) }
  let(:queue) { instance_double(Bunny::Queue) }
  let(:instance) { Class.new(Ears::Consumer).new(channel, queue) }
  let(:delivery_info) do
    instance_double(Bunny::DeliveryInfo, delivery_tag: delivery_tag)
  end
  let(:delivery_tag) { 1 }
  let(:metadata) { instance_double(Bunny::MessageProperties) }
  let(:payload) { 'my payload' }

  before do
    allow(channel).to receive(:generate_consumer_tag).and_return('test')
    allow(channel).to receive(:number).and_return(1)
    allow(channel).to receive(:ack).with(delivery_tag, false)
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
      expect(instance).to receive(:work)
        .with(delivery_info, metadata, payload)
        .and_return(:ack)

      instance.process_delivery(delivery_info, metadata, payload)
    end

    it 'returns the result of #work' do
      allow(instance).to receive(:work).and_return(:ack)

      expect(instance.process_delivery(delivery_info, metadata, payload)).to eq(
        :ack,
      )
    end

    it 'acks the message if #work returns :ack' do
      allow(instance).to receive(:work).and_return(:ack)

      expect(channel).to receive(:ack).with(delivery_tag, false)

      instance.process_delivery(delivery_info, metadata, payload)
    end

    it 'rejects the message if #work returns :reject' do
      allow(instance).to receive(:work).and_return(:reject)

      expect(channel).to receive(:reject).with(delivery_tag)

      instance.process_delivery(delivery_info, metadata, payload)
    end

    it 'requeues the message if #work returns :requeue' do
      allow(instance).to receive(:work).and_return(:requeue)

      expect(channel).to receive(:reject).with(delivery_tag, true)

      instance.process_delivery(delivery_info, metadata, payload)
    end

    it 'raises an error if #work does not return a valid symbol' do
      allow(instance).to receive(:work).and_return(:blorg)

      expect {
        instance.process_delivery(delivery_info, metadata, payload)
      }.to raise_error(
        Ears::Consumer::InvalidReturnError,
        '#work must return :ack, :reject or :requeue, received :blorg instead',
      )
    end
  end

  describe '#ack' do
    let(:instance) do
      Class.new(Ears::Consumer) do
        def work
          ack
        end
      end.new(channel, queue)
    end

    it 'returns :ack when called in #work' do
      expect(instance.work).to eq(:ack)
    end
  end

  describe '#reject' do
    let(:instance) do
      Class.new(Ears::Consumer) do
        def work
          reject
        end
      end.new(channel, queue)
    end

    it 'returns :reject when called in #work' do
      expect(instance.work).to eq(:reject)
    end
  end

  describe '#requeue' do
    let(:instance) do
      Class.new(Ears::Consumer) do
        def work
          requeue
        end
      end.new(channel, queue)
    end

    it 'returns :requeue when called in #work' do
      expect(instance.work).to eq(:requeue)
    end
  end
end
