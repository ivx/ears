require 'rspec/mocks'

module Ears
  module Testing
    module TestHelper
      include RSpec::Mocks::ExampleMethods

      def mock_ears(*exchange_names)
        Ears::Testing.message_capture ||= MessageCapture.new

        @original_connection = Ears.instance_variable_get(:@connection)

        publisher_mock =
          PublisherMock.new(exchange_names, Ears::Testing.message_capture)
        publisher_mock.setup_mocks
      end

      def ears_reset!
        Ears::Testing.message_capture = nil

        if instance_variable_defined?(:@original_connection)
          Ears.instance_variable_set(:@connection, @original_connection)
          remove_instance_variable(:@original_connection)
        end

        if defined?(Ears::PublisherChannelPool)
          Ears::PublisherChannelPool.reset!
        end
      end

      def published_messages(exchange_name = nil, routing_key: nil)
        return [] unless Ears::Testing.message_capture

        messages = exchange_name ? messages_for(exchange_name) : all_messages
        routing_key ? filter_for_routing_key(messages, routing_key) : messages
      end

      def last_published_message(exchange_name = nil)
        published_messages(exchange_name).last
      end

      def last_published_payload(exchange_name = nil)
        last_published_message(exchange_name).data
      end

      def clear_published_messages
        Ears::Testing.message_capture&.clear
      end

      private

      def messages_for(exchange_name)
        Ears::Testing.message_capture.messages_for(exchange_name)
      end

      def all_messages
        Ears::Testing.message_capture.all_messages
      end

      def filter_for_routing_key(messages, routing_key)
        messages.select { |message| message.routing_key.include?(routing_key) }
      end
    end
  end
end
