require 'bunny'
require 'multi_json'

module Ears
  # Publisher for sending messages to RabbitMQ exchanges.
  class Publisher
    # Error that is raised when publishing fails
    class PublishError < StandardError
      def initialize(exchange_name, routing_key, error)
        super(
          "Failed to publish to exchange '#{exchange_name}' with routing key '#{routing_key}': #{error.message}",
        )
      end
    end

    # @return [String] The name of the exchange to publish to
    attr_reader :exchange_name

    # @return [Symbol] The type of the exchange (:direct, :fanout, :topic or :headers)
    attr_reader :exchange_type

    # @return [Hash] The options for the exchange
    attr_reader :exchange_options

    # Creates a new publisher for the specified exchange.
    #
    # @param [String] exchange_name The name of the exchange to publish to.
    # @param [Symbol] exchange_type The type of the exchange (:direct, :fanout, :topic or :headers).
    # @param [Hash] exchange_options The options for the exchange. These are passed on to +Bunny::Exchange.new+.
    def initialize(exchange_name, exchange_type = :topic, exchange_options = {})
      @exchange_name = exchange_name
      @exchange_type = exchange_type
      @exchange_options = { durable: true }.merge(exchange_options)
      @exchange = nil
    end

    # Publishes a JSON message to the configured exchange.
    #
    # @param [Hash, Array, Object] data The data to serialize as JSON and publish.
    # @param [String] routing_key The routing key for the message.
    # @param [Hash] options Additional options for publishing.
    #
    # @raise [PublishError] if publishing fails
    # @return [void]
    def publish(data, routing_key:, **options)
      publish_options = default_publish_options.merge(options)

      exchange.publish(
        MultiJson.dump(data),
        { routing_key: routing_key }.merge(publish_options),
      )
    rescue => e
      raise PublishError.new(exchange_name, routing_key, e)
    end

    # Closes and resets the exchange, forcing it to be recreated on next use.
    # This can be useful for connection recovery scenarios.
    #
    # @return [void]
    def reset!
      @exchange = nil
    end

    private

    def exchange
      @exchange ||= create_exchange
    end

    def create_exchange
      Bunny::Exchange.new(
        Ears.channel,
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
  end
end
