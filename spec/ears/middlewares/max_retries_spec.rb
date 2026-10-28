require 'bunny'
require 'ears/middlewares/max_retries'
require 'time'

RSpec.describe Ears::Middlewares::MaxRetries do
  let(:delivery_info) { instance_double(Bunny::DeliveryInfo) }
  let(:properties) do
    {
      headers: {
        'x-death' => [
          {
            'count' => 10,
            'exchange' => '',
            'queue' => 'my_queue.retry',
            'reason' => 'expired',
            'routing-keys' => ['my_queue.retry'],
            'time' => Time.parse('2021-09-10T10:56:22Z'),
          },
          {
            'count' => 2,
            'reason' => 'rejected',
            'queue' => 'my_queue',
            'time' => Time.parse('2021-09-10T10:56:20Z'),
            'exchange' => 'my_exchange',
            'routing-keys' => [''],
          },
        ],
        'x-first-death-queue' => 'my_queue',
        'x-last-death-reason' => 'rejected',
        'tenant' => 'acme',
      },
      delivery_mode: 2,
      content_type: 'application/json',
      content_encoding: 'utf-8',
      priority: 5,
      correlation_id: 'correlation-1',
      reply_to: 'reply-queue',
      message_id: 'message-1',
      timestamp: Time.parse('2021-09-10T10:56:00Z'),
      type: 'order.created',
      user_id: 'original-user',
      app_id: 'order-service',
    }
  end
  let(:metadata) { Bunny::MessageProperties.new(properties) }
  let(:payload) { 'payload' }
  let(:error_queue) { 'my_queue.error' }
  let(:middleware) do
    Ears::Middlewares::MaxRetries.new(
      { retries: max_retries, error_queue: error_queue },
    )
  end
  let(:max_retries) { 2 }
  let(:channel) { instance_double(Bunny::Channel) }
  let(:default_exchange) { instance_double(Bunny::Exchange) }

  before do
    allow(Ears).to receive(:channel).and_return(channel)

    allow(Bunny::Exchange).to receive(:default).and_return(default_exchange)
  end

  context 'when retry count is not exceeded' do
    it 'returns the result of the downstream middleware' do
      expect(
        middleware.call(delivery_info, metadata, payload, Proc.new { :moep }),
      ).to eq(:moep)
    end
  end

  context 'when retry count is exceeded' do
    let(:max_retries) { 1 }
    let(:published_options) { [] }

    before do
      allow(default_exchange).to receive(:publish) do |_payload, **options|
        published_options << options
      end
    end

    it 'acks the message when the max retry count is exceeded' do
      expect(
        middleware.call(delivery_info, metadata, payload, Proc.new { :moep }),
      ).to eq(:ack)
    end

    it 'publishes the unchanged payload to the configured error queue' do
      expect(Bunny::Exchange).to receive(:default).with(channel).and_return(
        default_exchange,
      )

      middleware.call(delivery_info, metadata, payload, Proc.new { :moep })

      expect(default_exchange).to have_received(:publish).with(
        payload,
        hash_including(routing_key: error_queue),
      )
    end

    it 'publishes the message as persistent' do
      middleware.call(delivery_info, metadata, payload, Proc.new { :moep })

      expect(published_options.first).to include(delivery_mode: 2)
    end

    it 'publishes as persistent when the original message was transient' do
      properties[:delivery_mode] = 1

      middleware.call(delivery_info, metadata, payload, Proc.new { :moep })

      expect(published_options.first).to include(delivery_mode: 2)
    end

    it 'copies the properties of the original message' do
      middleware.call(delivery_info, metadata, payload, Proc.new { :moep })

      expect(published_options.first).to include(
        content_type: 'application/json',
        content_encoding: 'utf-8',
        priority: 5,
        correlation_id: 'correlation-1',
        reply_to: 'reply-queue',
        message_id: 'message-1',
        timestamp: Time.parse('2021-09-10T10:56:00Z').to_i,
        type: 'order.created',
        app_id: 'order-service',
      )
    end

    it 'removes the x-death header and keeps the other headers' do
      middleware.call(delivery_info, metadata, payload, Proc.new { :moep })

      expect(published_options.first[:headers]).to eq(
        'x-first-death-queue' => 'my_queue',
        'x-last-death-reason' => 'rejected',
        'tenant' => 'acme',
      )
    end

    it 'does not copy the user id' do
      middleware.call(delivery_info, metadata, payload, Proc.new { :moep })

      expect(published_options.first).not_to have_key(:user_id)
    end

    it 'does not change the metadata of the original message' do
      middleware.call(delivery_info, metadata, payload, Proc.new { :moep })

      expect(properties[:headers]).to have_key('x-death')
      expect(properties).to include(user_id: 'original-user', delivery_mode: 2)
    end
  end

  context 'when publishing through a real Bunny channel' do
    let(:max_retries) { 1 }
    let(:connection) do
      instance_double(
        Bunny::Session,
        logger: Logger.new(nil),
        next_channel_id: 1,
        register_channel: nil,
        mutex_impl: Mutex,
        transport_write_timeout: 1,
        send_frameset: nil,
        record_exchange: nil,
      )
    end
    let(:channel) { Bunny::Channel.new(connection) }
    let(:default_exchange) { Bunny::Exchange.default(channel) }
    let(:header_frame) do
      sent_frames = nil
      allow(connection).to receive(:send_frameset) do |frames, _channel|
        sent_frames = frames
      end

      middleware.call(delivery_info, metadata, payload, Proc.new { :moep })

      sent_frames.find { |frame| frame.is_a?(AMQ::Protocol::HeaderFrame) }
    end

    before do
      channel.instance_variable_set(:@status, :open)
      channel.instance_variable_set(:@frame_max, 131_072)
      allow(Bunny::Exchange).to receive(:default).and_call_original
    end

    it 'sends the message with delivery mode persistent' do
      properties[:delivery_mode] = 1

      expect(header_frame.properties[:delivery_mode]).to eq(2)
    end

    it 'sends the copied properties and headers without x-death' do
      expect(header_frame.properties).to include(
        message_id: 'message-1',
        content_type: 'application/json',
        headers: hash_excluding('x-death'),
      )
    end

    it 'sends the original timestamp' do
      expect(header_frame.properties[:timestamp]).to eq(
        Time.parse('2021-09-10T10:56:00Z'),
      )
    end

    it 'sends no user id' do
      expect(header_frame.properties).not_to have_key(:user_id)
    end

    context 'when the original message has no timestamp' do
      before { properties.delete(:timestamp) }

      it 'sends the message without a timestamp' do
        expect(header_frame.properties).not_to have_key(:timestamp)
      end
    end
  end

  context 'when no death headers are present' do
    let(:metadata) { Bunny::MessageProperties.new({ headers: {} }) }

    it 'returns downstream result if no death headers are present' do
      expect(
        middleware.call(delivery_info, metadata, payload, Proc.new { :moep }),
      ).to eq(:moep)
    end
  end

  context 'when metadata has no headers' do
    let(:metadata) { Bunny::MessageProperties.new({ headers: nil }) }

    it 'returns downstream result if no death headers are present' do
      expect(
        middleware.call(delivery_info, metadata, payload, Proc.new { :moep }),
      ).to eq(:moep)
    end
  end
end
