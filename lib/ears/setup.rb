require 'bunny'
require 'ears/consumer'
require 'ears/consumer_wrapper'

module Ears
  # Contains methods used in {Ears.setup} to set up your exchanges, queues and consumers.
  class Setup
    # Creates a new exchange if it does not already exist.
    #
    # @param [String] name The name of the exchange.
    # @param [Symbol] type The type of the exchange (:direct, :fanout, :topic or :headers).
    # @param [Hash] opts The options for the exchange. These are passed on to +Bunny::Exchange.new+.
    # @return [Bunny::Exchange] The exchange that was either newly created or was already there.
    def exchange(name, type, opts = {})
      Bunny::Exchange.new(Ears.channel, type, name, opts)
    end

    # Creates a new queue if it does not already exist.
    #
    # @param [String] name The name of the queue.
    # @param [Hash] opts The options for the queue. These are passed on to +Bunny::Exchange.new+.
    # @return [Bunny::Queue] The queue that was either newly created or was already there.
    def queue(name, opts = {})
      Bunny::Queue.new(Ears.channel, name, opts)
    end

    # Creates and starts one or many consumers bound to the given queue.
    #
    # @param [Bunny::Queue] queue The queue the consumers should be subscribed to.
    # @param [Class<Ears::Consumer>] consumer_class A class implementing {Ears::Consumer} that holds the consumer behavior.
    # @param [Integer] threads The number of threads that should be used to process messages from the queue.
    # @param [Hash] args The arguments for the consumer. These are passed on to +Bunny::Consumer.new+.
    # @option args [Integer] :prefetch (1) The prefetch count used for this consumer.
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
      ConsumerWrapper.new(
        consumer_class.new,
        queue.channel,
        queue,
        "#{consumer_class.name}-#{number}",
        args,
      )
    end

    def create_consumer_channel(args)
      Ears
        .connection
        .create_channel(nil, 1, true)
        .tap do |channel|
          channel.prefetch(args.fetch(:prefetch, 1))
          channel.on_uncaught_exception { |error| Ears.error!(error) }
        end
    end

    def create_consumer_queue(queue, args)
      Bunny::Queue.new(create_consumer_channel(args), queue.name, queue.options)
    end
  end
end
