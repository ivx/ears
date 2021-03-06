require 'ears/consumer'

RSpec.describe Ears::Consumer do
  let(:channel) { instance_double(Bunny::Channel) }
  let(:queue) { instance_double(Bunny::Queue) }
  let(:instance) { Class.new(Ears::Consumer).new }
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

    it 'allows returning :ack' do
      allow(instance).to receive(:work).and_return(:ack)

      instance.process_delivery(delivery_info, metadata, payload)
    end

    it 'allows returning :reject' do
      allow(instance).to receive(:work).and_return(:reject)

      instance.process_delivery(delivery_info, metadata, payload)
    end

    it 'allows returning :requeue' do
      allow(instance).to receive(:work).and_return(:requeue)

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
      Class
        .new(Ears::Consumer) do
          def work(_delivery_info, _metadata, _payload)
            ack
          end
        end
        .new
    end

    it 'returns :ack when called in #work' do
      expect(instance.work(delivery_info, metadata, payload)).to eq(:ack)
    end
  end

  describe '#reject' do
    let(:instance) do
      Class
        .new(Ears::Consumer) do
          def work(_delivery_info, _metadata, _payload)
            reject
          end
        end
        .new
    end

    it 'returns :reject when called in #work' do
      expect(instance.work(delivery_info, metadata, payload)).to eq(:reject)
    end
  end

  describe '#requeue' do
    let(:instance) do
      Class
        .new(Ears::Consumer) do
          def work(_delivery_info, _metadata, _payload)
            requeue
          end
        end
        .new
    end

    it 'returns :requeue when called in #work' do
      expect(instance.work(delivery_info, metadata, payload)).to eq(:requeue)
    end
  end

  describe '.use' do
    let(:instance) do
      Class
        .new(Ears::Consumer) do
          use Middleware

          def work(_delivery_info, _metadata, _payload)
            ack
          end
        end
        .new
    end

    let(:instance_with_two_middlewares) do
      Class
        .new(Ears::Consumer) do
          use Middleware
          use SecondMiddleware

          def work(_delivery_info, _metadata, _payload)
            ack
          end
        end
        .new
    end

    let(:middleware) { class_double('Middleware').as_stubbed_const }
    let(:middleware_instance) { instance_double('Middleware') }
    let(:second_middleware) do
      class_double('SecondMiddleware').as_stubbed_const
    end
    let(:second_middleware_instance) { instance_double('SecondMiddleware') }

    it 'wraps the given middleware around the call to work' do
      expect(middleware).to receive(:new).and_return(middleware_instance)
      expect(middleware_instance).to receive(:call) do |d, m, p, app|
        expect(d).to eq(delivery_info)
        expect(m).to eq(metadata)
        expect(p).to eq(payload)
        app.call(d, m, p)
      end

      expect(instance.process_delivery(delivery_info, metadata, payload)).to eq(
        :ack,
      )
    end

    it 'calls middlewares in the correct order' do
      expect(middleware).to receive(:new)
        .and_return(middleware_instance)
        .ordered
      expect(second_middleware).to receive(:new)
        .and_return(second_middleware_instance)
        .ordered
      expect(middleware_instance).to receive(:call) do |d, m, p, app|
        app.call(d, m, p)
      end.ordered
      expect(second_middleware_instance).to receive(:call) do |d, m, p, app|
        app.call(d, m, p)
      end.ordered

      expect(
        instance_with_two_middlewares.process_delivery(
          delivery_info,
          metadata,
          payload,
        ),
      ).to eq(:ack)
    end
  end
end
