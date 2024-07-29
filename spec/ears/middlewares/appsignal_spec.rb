require 'bunny'
require 'ears/middlewares/appsignal'

RSpec.describe Ears::Middlewares::Appsignal do
  let(:delivery_info) { instance_double(Bunny::DeliveryInfo) }
  let(:metadata) { instance_double(Bunny::MessageProperties) }
  let(:payload) { 'payload' }
  let(:appsignal) { stub_const('Appsignal', Class.new) }
  let(:middleware) do
    Ears::Middlewares::Appsignal.new(class_name: 'MyConsumer')
  end
  let(:now) { Time.utc(2020) }

  before { allow(Time).to receive_message_chain(:now, :utc).and_return(now) }

  it 'returns the result of the downstream middleware' do
    expect(appsignal).to receive(:monitor).and_yield
    expect(
      middleware.call(delivery_info, metadata, payload, Proc.new { :moep }),
    ).to eq(:moep)
  end

  it 'starts an Appsignal transaction and calls the downstream middleware' do
    expect(appsignal).to receive(:monitor).with(
      namespace: 'background',
      action: 'MyConsumer#work',
    ).and_yield
    expect { |b|
      middleware.call(delivery_info, metadata, payload, Proc.new(&b))
    }.to yield_control
  end

  it 'calls set_error when an error is raised' do
    error = RuntimeError.new('moep')
    expect(appsignal).to receive(:monitor).and_yield
    expect(appsignal).to receive(:set_error).with(error)

    expect do
      middleware.call(
        delivery_info,
        metadata,
        payload,
        Proc.new { raise error },
      )
    end.to raise_error(error)
  end

  context 'with namespace' do
    let(:middleware) do
      Ears::Middlewares::Appsignal.new(
        namespace: 'cronjob',
        class_name: 'MyConsumer',
      )
    end

    it 'starts an Appsignal transaction with the given namespace and calls the downstream middleware' do
      expect(appsignal).to receive(:monitor).with(
        namespace: 'cronjob',
        action: 'MyConsumer#work',
      ).and_yield
      expect { |b|
        middleware.call(delivery_info, metadata, payload, Proc.new(&b))
      }.to yield_control
    end
  end
end
