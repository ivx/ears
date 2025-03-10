require 'bunny'

module Ears
  # The abstract base class for consumers processing messages from queues.
  # @abstract Subclass and override {#work} to implement.
  class Consumer
    # Error that is raised when an invalid value is returned from {#work}
    class InvalidReturnError < StandardError
      def initialize(value)
        super(
          "#work must return :ack, :reject or :requeue, received #{value.inspect} instead",
        )
      end
    end

    # List of registered middlewares. Register new middlewares with {.use}.
    # @return [Array<Ears::Middleware>]
    def self.middlewares
      @middlewares ||= []
    end

    # Registers a new middleware by instantiating +middleware+ and passing it +opts+.
    #
    # @param [Class<Ears::Middleware>] middleware The middleware class to instantiate and register.
    # @param [Hash] opts The options for instantiating the middleware.
    def self.use(middleware, opts = {})
      middlewares << middleware.new(opts)
    end

    # Configures the consumer, setting queue, exchange and other options to be used by
    # the add_consumer method.
    #
    # @param [Hash] opts The options to configure the consumer with.
    # @option opts [String] :queue The name of the queue to consume from.
    # @option opts [String] :exchange The name of the exchange the queue should be bound to.
    # @option opts [Array] :routing_keys The routing keys used for the queue binding.
    # @option opts [Boolean] :durable_queue (true) Whether the queue should be durable.
    # @option opts [Boolean] :retry_queue (false) Whether a retry queue should be provided.
    # @option opts [Integer] :retry_delay (5000) The delay in milliseconds before retrying a message.
    # @option opts [Boolean] :error_queue (false) Whether an error queue should be provided.
    # @option opts [Boolean] :durable_exchange (true) Whether the exchange should be durable.
    # @option opts [Symbol] :exchange_type (:topic) The type of exchange to use.
    # @option opts [Integer] :threads (1) The number of threads to use for this consumer.
    # @option opts [Hash] :arguments (nil) Additional arguments for the queue.
    # @option opts [Integer] :prefetch (1) The number of messages to prefetch.
    def self.configure(opts = {})
      self.queue = opts.fetch(:queue)
      self.exchange = opts.fetch(:exchange)
      self.routing_keys = opts.fetch(:routing_keys)
      self.queue_options = queue_options_from(opts: opts)
      self.durable_exchange = opts.fetch(:durable_exchange, true)
      self.exchange_type = opts.fetch(:exchange_type, :topic)
      self.threads = opts.fetch(:threads, 1)
      self.prefetch = opts.fetch(:prefetch, 1)
    end

    # The method that is called when a message from the queue is received.
    # Keep in mind that the parameters received can be altered by middlewares!
    #
    # @param [Bunny::DeliveryInfo] delivery_info The delivery info of the message.
    # @param [Bunny::MessageProperties] metadata The metadata of the message.
    # @param [String] payload The payload of the message.
    #
    # @return [:ack, :reject, :requeue] A symbol denoting what should be done with the message.
    def work(delivery_info, metadata, payload)
      raise NotImplementedError
    end

    # Wraps #work to add middlewares. This is being called by Ears when a message is received for the consumer.
    #
    # @param [Bunny::DeliveryInfo] delivery_info The delivery info of the received message.
    # @param [Bunny::MessageProperties] metadata The metadata of the received message.
    # @param [String] payload The payload of the received message.
    # @raise [InvalidReturnError] if you return something other than +:ack+, +:reject+ or +:requeue+ from {#work}.
    def process_delivery(delivery_info, metadata, payload)
      self
        .class
        .middlewares
        .reverse
        .reduce(work_proc) do |next_middleware, middleware|
          nest_middleware(middleware, next_middleware)
        end
        .call(delivery_info, metadata, payload)
    end

    protected

    # Helper method to ack a message.
    #
    # @return [:ack]
    def ack
      :ack
    end

    # Helper method to reject a message.
    #
    # @return [:reject]
    #
    def reject
      :reject
    end

    # Helper method to requeue a message.
    #
    # @return [:requeue]
    def requeue
      :requeue
    end

    private

    def work_proc
      ->(delivery_info, metadata, payload) do
        work(delivery_info, metadata, payload).tap do |result|
          verify_result(result)
        end
      end
    end

    def nest_middleware(middleware, next_middleware)
      ->(delivery_info, metadata, payload) do
        middleware.call(delivery_info, metadata, payload, next_middleware)
      end
    end

    def verify_result(result)
      unless %i[ack reject requeue].include?(result)
        raise InvalidReturnError, result
      end
    end

    class << self
      attr_reader :queue,
                  :exchange,
                  :routing_keys,
                  :queue_options,
                  :durable_exchange,
                  :exchange_type,
                  :threads,
                  :prefetch

      private

      def queue_options_from(opts:)
        {
          durable: opts.fetch(:durable_queue, true),
          retry_queue: opts.fetch(:retry_queue, false),
          retry_delay: opts.fetch(:retry_delay, 5000),
          error_queue: opts.fetch(:error_queue, false),
          arguments: opts.fetch(:arguments, nil),
        }.compact
      end

      attr_writer :queue,
                  :exchange,
                  :routing_keys,
                  :queue_options,
                  :durable_exchange,
                  :exchange_type,
                  :threads,
                  :prefetch
    end
  end
end
