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
      self.class.middlewares.reverse.reduce(
        work_proc,
      ) do |next_middleware, middleware|
        nest_middleware(middleware, next_middleware)
      end.call(delivery_info, metadata, payload)
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
  end
end
