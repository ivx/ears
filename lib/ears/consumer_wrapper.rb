require 'bunny'

module Ears
  class ConsumerWrapper < Bunny::Consumer
    def initialize(consumer, channel, queue, consumer_tag, arguments = {})
      @consumer = consumer
      super(channel, queue, consumer_tag, false, false, arguments)
    end

    def process_delivery(delivery_info, metadata, payload)
      consumer
        .process_delivery(delivery_info, metadata, payload)
        .tap { |result| process_result(result, delivery_info.delivery_tag) }
    end

    private

    attr_reader :consumer

    def process_result(result, delivery_tag)
      case result
      when :ack
        channel.ack(delivery_tag, false)
      when :reject
        channel.reject(delivery_tag)
      when :requeue
        channel.reject(delivery_tag, true)
      else
        raise InvalidReturnError, result
      end
    end
  end
end
