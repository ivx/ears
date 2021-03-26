require 'bunny'

module Ears
  class Consumer < Bunny::Consumer
    def work(delivery_info, metadata, payload)
      raise NotImplementedError
    end

    def process_delivery(delivery_info, metadata, payload)
      work(delivery_info, metadata, payload).tap do |result|
        channel.ack(delivery_info.delivery_tag, false) if result == :ack
      end
    end

    protected

    def ack!
      :ack
    end
  end
end
