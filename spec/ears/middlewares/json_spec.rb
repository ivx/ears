require 'bunny'
require 'ears/middlewares/json'

RSpec.describe Ears::Middlewares::JSON do
  describe '#call' do
    let(:middleware) { Ears::Middlewares::JSON.new(options) }
    let(:delivery_info) { instance_double(Bunny::DeliveryInfo) }
    let(:metadata) { instance_double(Bunny::MessageProperties) }
    let(:payload) { MultiJson.dump({ my: 'payload' }) }
    let(:error_handler) { Proc.new { :error_handler_result } }
    let(:options) { { on_error: error_handler } }

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
      middleware =
        Ears::Middlewares::JSON.new(
          symbolize_keys: false,
          on_error: error_handler,
        )
      expect do |b|
        proc =
          Proc.new { |_, _, payload, _block|
            expect(payload).to eq({ 'my' => 'payload' })
            Proc.new(&b).call
          }
        middleware.call(delivery_info, metadata, payload, proc)
      end.to yield_control
    end

    it 'raises when initialized without error handler' do
      expect { Ears::Middlewares::JSON.new }.to raise_error(KeyError)
    end

    context 'when encountering an error' do
      let(:payload) { 'This is not JSON' }

      it 'returns the result of the error handler' do
        expect(
          middleware.call(
            delivery_info,
            metadata,
            payload,
            Proc.new { :success },
          ),
        ).to eq(:error_handler_result)
      end

      it 'calls the error handler with the error' do
        expect(error_handler).to receive(:call).with(
          instance_of(MultiJson::ParseError),
        )

        middleware.call(delivery_info, metadata, payload, Proc.new { :success })
      end
    end
  end
end
