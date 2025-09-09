module Ears
  module Testing
    class MessageCapture
      Message =
        Struct.new(
          :exchange_name,
          :routing_key,
          :data,
          :options,
          :timestamp,
          :thread_id,
          keyword_init: true,
        )

      def initialize
        @messages = {}
        @mutex = Mutex.new
      end

      def add_message(exchange_name, data, routing_key, options = {})
        @mutex.synchronize do
          @messages[exchange_name] ||= []

          message =
            Message.new(
              exchange_name: exchange_name,
              routing_key: routing_key,
              data: data,
              options: options,
              timestamp: Time.now,
              thread_id: Thread.current.object_id.to_s,
            )

          @messages[exchange_name] << message

          shift_messages(exchange_name)

          message
        end
      end

      def messages_for(exchange_name)
        @mutex.synchronize { (@messages[exchange_name] || []).dup }
      end

      def all_messages
        @mutex.synchronize { @messages.values.flatten }
      end

      def clear
        @mutex.synchronize { @messages.clear }
      end

      def count(exchange_name = nil)
        @mutex.synchronize do
          return (@messages[exchange_name] || []).size if exchange_name

          @messages.values.sum(&:size)
        end
      end

      def empty?
        @mutex.synchronize do
          @messages.empty? || @messages.values.all?(&:empty?)
        end
      end

      def find_messages(exchange_name: nil, routing_key: nil, data: nil)
        messages = exchange_name ? messages_for(exchange_name) : all_messages

        messages.select do |msg|
          next false if routing_key && msg.routing_key != routing_key
          next false if data && msg.data != data

          true
        end
      end

      private

      def shift_messages(exchange_name)
        max_messages = Ears::Testing.configuration.max_captured_messages
        if @messages[exchange_name].size > max_messages
          @messages[exchange_name].shift
        end
      end
    end
  end
end
