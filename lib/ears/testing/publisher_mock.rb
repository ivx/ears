require 'rspec/mocks'

module Ears
  module Testing
    class UnmockedExchangeError < StandardError
    end

    class PublisherMock
      include RSpec::Mocks::ExampleMethods

      def initialize(exchange_names, message_capture)
        @exchange_names = Array(exchange_names)
        @message_capture = message_capture
        @mock_exchanges = {}
      end

      def setup_mocks
        setup_connection
        setup_channel_pool
      end

      private

      attr_reader :exchange_names, :message_capture, :mock_exchanges

      def setup_connection
        mock_connection = instance_double(Bunny::Session, open?: true)
        Ears.instance_variable_set(:@connection, mock_connection)
      end

      def setup_channel_pool
        mock_channel = create_mock_channel
        allow(Ears::PublisherChannelPool).to receive(:with_channel).and_yield(
          mock_channel,
        )
        mock_channel
      end

      def create_mock_channel
        instance_double(Bunny::Channel).tap do |channel|
          setup_exchange_declare(channel)
          setup_register_exchange(channel)
          setup_basic_publish(channel)
          setup_publisher_confirms(channel)
        end
      end

      def setup_exchange_declare(channel)
        allow(channel).to receive(:exchange_declare) do |name, type, options|
          create_or_get_mock_exchange(name, type, options)
        end
      end

      def setup_register_exchange(channel)
        allow(channel).to receive(:register_exchange)
      end

      def setup_basic_publish(channel)
        allow(channel).to receive(
          :basic_publish,
        ) do |data, exchange, routing_key, options|
          if exchange_names.include?(exchange)
            capture_message(exchange, data, routing_key, options)
          elsif strict_mocking?
            raise_unmocked_exchange_error(exchange)
          end
        end
      end

      def setup_publisher_confirms(channel)
        allow(channel).to receive(:confirm_select)
        allow(channel).to receive(:wait_for_confirms).and_return(true)
        allow(channel).to receive(:nacked_set).and_return(Set.new)
        allow(channel).to receive(:open?).and_return(true)
        allow(channel).to receive(:close)
      end

      def create_or_get_mock_exchange(name, type, _options)
        mock_exchanges[name] ||= create_mock_exchange(name, type)
      end

      def create_mock_exchange(name, type)
        exchange = instance_double(Bunny::Exchange, name: name, type: type)

        setup_exchange_publish(exchange, name)

        exchange
      end

      def setup_exchange_publish(exchange, name)
        allow(exchange).to receive(:publish) do |data, routing_options|
          routing_key = routing_options[:routing_key]
          capture_message(name, data, routing_key, routing_options)
        end
      end

      def capture_message(exchange_name, data, routing_key, options)
        message_capture.add_message(exchange_name, data, routing_key, options)
      end

      def strict_mocking?
        Ears::Testing.configuration.strict_exchange_mocking
      end

      def raise_unmocked_exchange_error(exchange)
        raise UnmockedExchangeError,
              "Exchange '#{exchange}' has not been mocked. Add mock_ears('#{exchange}') to your test setup."
      end
    end
  end
end
