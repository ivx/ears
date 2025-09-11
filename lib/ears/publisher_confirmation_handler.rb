require 'ears/errors'

module Ears
  # Handles publisher confirmations for RabbitMQ messages.
  #
  # This class encapsulates the logic for publishing messages with confirmations,
  # including timeout handling, channel cleanup, and pool coordination.
  class PublisherConfirmationHandler
    # Creates a new confirmation handler.
    #
    # @param [Ears::Configuration] config The Ears configuration object.
    # @param [Logger] logger The logger instance for warnings and errors.
    def initialize(config:, logger:)
      @config = config
      @logger = logger
    end

    # Publishes a message with confirmation.
    #
    # @param [Bunny::Channel] channel The channel to use for publishing.
    # @param [Bunny::Exchange] exchange The exchange to publish to.
    # @param [Hash, Array, Object] data The data to publish.
    # @param [String] routing_key The routing key for the message.
    # @param [Hash] options The publish options.
    #
    # @raise [PublishConfirmationTimeout] if confirmation times out
    # @raise [PublishNacked] if message is nacked by the broker
    # @return [void]
    def publish_with_confirmation(
      channel:,
      exchange:,
      data:,
      routing_key:,
      options:
    )
      exchange.publish(data, { routing_key: routing_key }.merge(options))

      timeout = config.publisher_confirms_timeout
      unless wait_for_confirms_with_timeout(channel, timeout)
        handle_confirmation_failure(channel, timeout)
      end
    end

    private

    attr_reader :config, :logger

    def wait_for_confirms_with_timeout(channel, timeout)
      return channel.wait_for_confirms if timeout.nil?

      waiter = Thread.new { channel.wait_for_confirms }

      return waiter.value if waiter.join(timeout)

      begin
        channel.close if channel.open?
      rescue StandardError => e
        warn("Failed closing channel on timeout: #{e.message}")
      end

      cleanup_timeout = config.publisher_confirms_cleanup_timeout
      waiter.join(cleanup_timeout) ||
        warn('Confirm waiter did not stop promptly after close')

      false
    end

    def handle_confirmation_failure(channel, timeout)
      begin
        channel.close if channel&.open?
      rescue StandardError => e
        warn("Failed closing channel on failed confirmation: #{e.message}")
      end

      PublisherChannelPool.reset_confirms_pool!

      if channel.nacked_set&.any?
        warn('Publisher confirmation failed: message was nacked by broker.')
        raise PublishNacked, 'Message was nacked by broker'
      else
        warn("Publisher confirmation failed: timeout after #{timeout}s.")
        raise PublishConfirmationTimeout,
              "Confirmation timeout after #{timeout}s"
      end
    end

    def warn(message)
      logger.warn(message)
    end
  end
end
