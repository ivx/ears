require 'bunny'
require 'ears/publisher_channel_pool'

module Ears
  # Publisher for sending messages to RabbitMQ exchanges.
  #
  # This is an experimental implementation, do not use it in production environments.
  #
  # Uses a connection pool for thread-safe publishing with configurable pool size.
  # This provides better performance and thread safety compared to using per-thread channels.
  class Publisher
    class PublishToStaleChannelError < StandardError
    end

    # Connection errors that should trigger retries
    CONNECTION_ERRORS = [
      PublishToStaleChannelError,
      Bunny::ConnectionClosedError,
      Bunny::NetworkFailure,
      IOError,
    ].freeze

    ##

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

      attempt = 1

      begin
        publish_with_channel(data:, routing_key:, publish_options:)
      rescue *CONNECTION_ERRORS => e
        connect_after_error(e)

        logger.info('Resetting channel pool after connection recovery')
        PublisherChannelPool.reset!

        publish_with_channel(data:, routing_key:, publish_options:)
      rescue StandardError => e
        attempt += 1

        raise e if attempt > config.publisher_max_retries

        sleep(retry_backoff_delay(attempt))
        retry
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
      unless Ears.connection.open?
        raise PublishToStaleChannelError, 'Connection is not open'
      end

      PublisherChannelPool.with_channel do |channel|
        exchange = create_exchange(channel)
        exchange.publish(
          data,
          { routing_key: routing_key }.merge(publish_options),
        )
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

    def connect_after_error(original_error)
      connection_attempt = 0

      logger.info('Trying to reconnect after connection error')
      while !Ears.connection.open?
        logger.info(
          "Connection still closed, attempt #{connection_attempt + 1}",
        )
        connection_attempt += 1

        if connection_attempt > config.publisher_connection_attempts
          logger.error('Connection attempts exhausted, giving up')

          raise original_error
        end

        sleep(connection_backoff_delay(connection_attempt))
      end
    end

    def retry_backoff_delay(attempt)
      config.publisher_retry_base_delay *
        (config.publisher_retry_backoff_factor**(attempt - 1))
    end

    def connection_backoff_delay(attempt)
      config.publisher_connection_base_delay *
        (config.publisher_connection_backoff_factor**(attempt - 1))
    end
  end
end
