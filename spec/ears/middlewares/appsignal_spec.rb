require 'bunny'
require 'ears/middlewares/appsignal'

RSpec.describe Ears::Middlewares::Appsignal do
  let(:delivery_info) { instance_double(Bunny::DeliveryInfo) }
  let(:metadata) { instance_double(Bunny::MessageProperties) }
  let(:payload) { 'payload' }
  let(:appsignal) { class_double('Appsignal').as_stubbed_const }
  let(:middleware) do
    Ears::Middlewares::Appsignal.new(
      transaction_name: 'perform_job.test',
      class_name: 'MyConsumer',
    )
  end
  let(:now) { Time.utc(2020) }

  before { allow(Time).to receive_message_chain(:now, :utc).and_return(now) }

  it 'returns the result of the downstream middleware' do
    expect(appsignal).to receive(:monitor_transaction).and_yield
    expect(
      middleware.call(delivery_info, metadata, payload, Proc.new { :moep }),
    ).to eq(:moep)
  end

  it 'starts an Appsignal transaction and calls the downstream middleware' do
    expect(appsignal).to receive(:monitor_transaction)
      .with(
        'perform_job.test',
        class: 'MyConsumer',
        method: 'work',
        queue_start: now,
      )
      .and_yield
    expect { |b|
      middleware.call(delivery_info, metadata, payload, Proc.new(&b))
    }.to yield_control
  end
end
