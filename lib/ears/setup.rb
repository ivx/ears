require 'bunny'
require 'ears/consumer'
require 'ears/consumer_wrapper'

module Ears
  # Contains methods used in {Ears.setup} to set up your exchanges, queues and consumers.
  class Setup
    QUEUE_PARAMS = %i[retry_queue retry_delay error_queue]

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
    # @option args [Boolean] :retry_queue (false) Whether a retry queue should be created. The retry queue is configured as a dead-letter-exchange of the original queue automatically. The name of the queue will be the given name suffixed with ".retry".
    # @option args [Integer] :retry_delay (5000) How long (in ms) a retried message is delayed before being routed back to the original queue.
    # @option args [Boolean] :error_queue (false) Whether an error queue should be created. The name of the queue will be the given name suffixed with ".error".
    # @return [Bunny::Queue] The queue that was either newly created or was already there.
    def queue(name, opts = {})
      bunny_opts = opts.reject { |k, _| QUEUE_PARAMS.include?(k) }
      retry_args = retry_arguments(name, opts)
      retry_delay = opts.fetch(:retry_delay, 5000)

      create_retry_queue(name, retry_delay, bunny_opts) if opts[:retry_queue]
      create_error_queue(name, bunny_opts) if opts[:error_queue]

      Bunny::Queue.new(
        Ears.channel,
        name,
        queue_options(bunny_opts, retry_args)
      )
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
        consumer = create_consumer(consumer_queue, consumer_class, args, n + 1)
        consumer.on_delivery do |delivery_info, metadata, payload|
          consumer.process_delivery(delivery_info, metadata, payload)
        end
        consumer_queue.subscribe_with(consumer)
      end
    end

    private

    def queue_options(bunny_opts, retry_arguments)
      return bunny_opts unless retry_arguments

      arguments = bunny_opts.fetch(:arguments, {})
      bunny_opts.merge({ arguments: arguments.merge(retry_arguments) })
    end

    def retry_arguments(name, opts)
      return unless opts[:retry_queue]

      {
        'x-dead-letter-exchange' => '',
        'x-dead-letter-routing-key' => "#{name}.retry"
      }
    end

    def create_consumer(queue, consumer_class, args, number)
      ConsumerWrapper.new(
        consumer_class.new,
        queue.channel,
        queue,
        "#{consumer_class.name}-#{number}",
        args
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

    def create_retry_queue(name, delay, opts)
      Bunny::Queue.new(
        Ears.channel,
        "#{name}.retry",
        opts.merge(retry_queue_opts(name, delay))
      )
    end

    def retry_queue_opts(name, delay)
      {
        arguments: {
          'x-message-ttl' => delay,
          'x-dead-letter-exchange' => '',
          'x-dead-letter-routing-key' => name
        }
      }
    end

    def create_error_queue(name, opts)
      Bunny::Queue.new(Ears.channel, "#{name}.error", opts)
    end
  end
end
