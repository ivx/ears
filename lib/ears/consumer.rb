require 'bunny'

module Ears
  class Consumer < Bunny::Consumer
    class InvalidReturnError < StandardError
      def initialize(value)
        super(
          "#work must return :ack, :reject or :requeue, received #{value.inspect} instead",
        )
      end
    end

    def work(delivery_info, metadata, payload)
      raise NotImplementedError
    end

    def process_delivery(delivery_info, metadata, payload)
      work(delivery_info, metadata, payload).tap do |result|
        process_result(result, delivery_info.delivery_tag)
      end
    end

    protected

    def ack
      :ack
    end

    def reject
      :reject
    end

    def requeue
      :requeue
    end

    private

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
