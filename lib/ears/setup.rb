require 'bunny'
require 'ears/consumer'

module Ears
  class Setup
    def exchange(name, type)
      Bunny::Exchange.new(Ears.channel, type, name)
    end

    def queue(name)
      Bunny::Queue.new(Ears.channel, name)
    end

    def consumer(queue, consumer_class, args = {})
      consumer =
        consumer_class.new(
          queue.channel,
          queue,
          consumer_class.name,
          false,
          false,
          args,
        )
      consumer.on_delivery do |delivery_info, metadata, payload|
        consumer.work(delivery_info, metadata, payload)
      end
      queue.subscribe_with(consumer)
    end
  end
end
