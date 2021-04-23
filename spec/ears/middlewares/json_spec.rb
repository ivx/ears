require 'bunny'
require 'ears/middlewares/json'

RSpec.describe Ears::Middlewares::JSON do
  describe '#call' do
    let(:delivery_info) { instance_double(Bunny::DeliveryInfo) }
    let(:metadata) { instance_double(Bunny::MessageProperties) }
    let(:payload) { MultiJson.dump({ my: 'payload' }) }

    it 'returns the result of the downstream middleware' do
      expect(
        Ears::Middlewares::JSON.call(
          delivery_info,
          metadata,
          payload,
          Proc.new { :moep },
        ),
      ).to eq(:moep)
    end

    it 'calls the next middleware with a parsed payload' do
      expect do |b|
        Ears::Middlewares::JSON.call(
          delivery_info,
          metadata,
          payload,
          Proc.new(&b),
        )
      end.to yield_control
    end
  end
end
