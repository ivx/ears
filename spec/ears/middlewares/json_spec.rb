require 'bunny'
require 'ears/middlewares/json'

RSpec.describe Ears::Middlewares::JSON do
  describe '#call' do
    let(:delivery_info) { instance_double(Bunny::DeliveryInfo) }
    let(:metadata) { instance_double(Bunny::MessageProperties) }
    let(:payload) { MultiJson.dump({ my: 'payload' }) }
    let(:middleware) { Ears::Middlewares::JSON.new }

    it 'returns the result of the downstream middleware' do
      expect(
        middleware.call(delivery_info, metadata, payload, Proc.new { :moep }),
      ).to eq(:moep)
    end

    it 'calls the next middleware with a parsed payload' do
      expect do |b|
        proc =
          Proc.new { |_, _, payload, _block|
            expect(payload).to eq({ my: 'payload' })
            Proc.new(&b).call
          }
        middleware.call(delivery_info, metadata, payload, proc)
      end.to yield_control
    end

    it 'can opt out of symbol keys' do
      middleware = Ears::Middlewares::JSON.new(symbolize_keys: false)
      expect do |b|
        proc =
          Proc.new { |_, _, payload, _block|
            expect(payload).to eq({ 'my' => 'payload' })
            Proc.new(&b).call
          }
        middleware.call(delivery_info, metadata, payload, proc)
      end.to yield_control
    end
  end
end
