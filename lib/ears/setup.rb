require 'bunny'
require 'ears/consumer'

module Ears
  class Setup
    def exchange(name, type, opts = {})
      Bunny::Exchange.new(Ears.channel, type, name, opts)
    end

    def queue(name, opts = {})
      Bunny::Queue.new(Ears.channel, name, opts)
    end

    def consumer(queue, consumer_class, threads = 1, args = {})
      threads.times do |n|
        consumer_queue = create_consumer_queue(queue, args)
        create_consumer(consumer_queue, consumer_class, args, n + 1)
          .tap do |consumer|
          consumer.on_delivery do |delivery_info, metadata, payload|
            consumer.process_delivery(delivery_info, metadata, payload)
          end
          consumer_queue.subscribe_with(consumer)
        end
      end
    end

    private

    def create_consumer(queue, consumer_class, args, number)
      consumer_class.new(
        queue.channel,
        queue,
        "#{consumer_class.name}-#{number}",
        false,
        false,
        args,
      )
    end

    def create_consumer_channel(args)
      Ears
        .connection
        .create_channel(nil, 1, true)
        .tap do |channel|
          channel.prefetch(args.fetch(:prefetch, 1))
          channel.on_uncaught_exception { |error| Thread.main.raise(error) }
        end
    end

    def create_consumer_queue(queue, args)
      Bunny::Queue.new(create_consumer_channel(args), queue.name, queue.options)
    end
  end
end
