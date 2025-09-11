require 'bunny'
require 'ears/publisher_channel_pool'
require 'ears/publisher_retry_handler'
require 'ears/publisher_confirmation_support'
require 'ears/errors'

module Ears
  # Publisher for sending messages to RabbitMQ exchanges.
  #
  # Uses a connection pool for thread-safe publishing with configurable pool size.
  # This provides better performance and thread safety compared to using per-thread channels.
  class Publisher
    include PublisherConfirmationSupport
    # Creates a new publisher for the specified exchange.
    #
    # @param [String] exchange_name The name of the exchange to publish to.
    # @param [Symbol] exchange_type The type of the exchange (:direct, :fanout, :topic or :headers).
    # @param [Hash] exchange_options The options for the exchange. These are passed on to +Bunny::Exchange.new+.
    def initialize(exchange_name, exchange_type = :topic, exchange_options = {})
      @exchange_name = exchange_name
      @exchange_type = exchange_type
      @exchange_options = { durable: true }.merge(exchange_options)
      @config = Ears.configuration
      @logger = Ears.configuration.logger
    end

    # Publishes a JSON message to the configured exchange.
    #
    # @param [Hash, Array, Object] data The data to serialize as JSON and publish.
    # @param [String] routing_key The routing key for the message.
    #
    # @option opts [String] :routing_key Routing key
    # @option opts [Boolean] :persistent Should the message be persisted to disk?
    # @option opts [Boolean] :mandatory Should the message be returned if it cannot be routed to any queue?
    # @option opts [Integer] :timestamp A timestamp associated with this message
    # @option opts [Integer] :expiration Expiration time after which the message will be deleted
    # @option opts [String] :type Message type, e.g. what type of event or command this message represents. Can be any string
    # @option opts [String] :reply_to Queue name other apps should send the response to
    # @option opts [String] :content_type Message content type (e.g. application/json)
    # @option opts [String] :content_encoding Message content encoding (e.g. gzip)
    # @option opts [String] :correlation_id Message correlated to this one, e.g. what request this message is a reply for
    # @option opts [Integer] :priority Message priority, 0 to 9. Not used by RabbitMQ, only applications
    # @option opts [String] :message_id Any message identifier
    # @option opts [String] :user_id Optional user ID. Verified by RabbitMQ against the actual connection username
    # @option opts [String] :app_id Optional application ID
    #
    # @raise [PublishError] if publishing fails
    # @return [void]
    def publish(data, routing_key:, **options)
      publish_options = default_publish_options.merge(options)

      retry_handler.run do
        publish_with_channel(data:, routing_key:, publish_options:)
      end
    end

    # Publishes a message to the configured exchange with confirmation.
    # Waits for RabbitMQ to confirm the message was received.
    #
    # @param [Hash, Array, Object] data The data to serialize as JSON and publish.
    # @param [String] routing_key The routing key for the message.
    # @param [Float] timeout The timeout in seconds for waiting for confirmation.
    #
    # @option opts [String] :routing_key Routing key
    # @option opts [Boolean] :persistent Should the message be persisted to disk?
    # @option opts [Boolean] :mandatory Should the message be returned if it cannot be routed to any queue?
    # @option opts [Integer] :timestamp A timestamp associated with this message
    # @option opts [Integer] :expiration Expiration time after which the message will be deleted
    # @option opts [String] :type Message type, e.g. what type of event or command this message represents. Can be any string
    # @option opts [String] :reply_to Queue name other apps should send the response to
    # @option opts [String] :content_type Message content type (e.g. application/json)
    # @option opts [String] :content_encoding Message content encoding (e.g. gzip)
    # @option opts [String] :correlation_id Message correlated to this one, e.g. what request this message is a reply for
    # @option opts [Integer] :priority Message priority, 0 to 9. Not used by RabbitMQ, only applications
    # @option opts [String] :message_id Any message identifier
    # @option opts [String] :user_id Optional user ID. Verified by RabbitMQ against the actual connection username
    # @option opts [String] :app_id Optional application ID
    #
    # @raise [PublishConfirmationTimeout] if confirmation times out
    # @raise [PublishNacked] if message is nacked by the broker
    # @return [void]
    def publish_with_confirmation(data, routing_key:, timeout: nil, **options)
      timeout ||= @config.publisher_confirms_timeout
      publish_options = default_publish_options.merge(options)

      retry_handler.run do
        publish_with_confirms(
          data: data,
          routing_key: routing_key,
          publish_options: publish_options,
          timeout: timeout,
        )
      end
    end

    # Resets the channel pool, forcing new channels to be created.
    # This can be useful for connection recovery scenarios.
    #
    # @return [void]
    def reset!
      PublisherChannelPool.reset!
    end

    private

    attr_reader :exchange_name,
                :exchange_type,
                :exchange_options,
                :config,
                :logger

    def publish_with_channel(data:, routing_key:, publish_options:)
      validate_connection!

      PublisherChannelPool.with_channel(confirms: false) do |channel|
        exchange = create_exchange(channel)
        exchange.publish(
          data,
          { routing_key: routing_key }.merge(publish_options),
        )
      end
    end

    def validate_connection!
      unless Ears.connection.open?
        raise PublisherRetryHandler::PublishToStaleChannelError,
              'Connection is not open'
      end
    end

    def create_exchange(channel)
      Bunny::Exchange.new(
        channel,
        exchange_type,
        exchange_name,
        exchange_options,
      )
    end

    def default_publish_options
      {
        persistent: true,
        timestamp: Time.now.to_i,
        headers: {
        },
        content_type: 'application/json',
      }
    end

    def retry_handler
      @retry_handler ||= PublisherRetryHandler.new(config, logger)
    end
  end
end
