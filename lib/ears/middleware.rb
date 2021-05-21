module Ears
  # The abstract base class for middlewares.
  # @abstract Subclass and override {#call} (and maybe +#initialize+) to implement.
  class Middleware
    # Invokes the middleware.
    #
    # @param [Bunny::DeliveryInfo] delivery_info The delivery info of the received message.
    # @param [Bunny::MessageProperties] metadata The metadata of the received message.
    # @param [String] payload The payload of the received message.
    # @param app The next middleware to call or the actual consumer instance.
    def call(delivery_info, metadata, payload, app)
      raise NotImplementedError
    end
  end
end
