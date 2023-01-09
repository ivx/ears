module Ears
  # The class representing the global {Ears} configuration.
  class Configuration
    class ConnectionNameMissing < StandardError
    end

    DEFAULT_RABBITMQ_URL = 'amqp://guest:guest@localhost:5672'

    # @return [String] the connection string for RabbitMQ.
    attr_accessor :rabbitmq_url

    # @return [String] the name for the RabbitMQ connection.
    attr_accessor :connection_name

    # @return [Boolean] if the recover_from_connection_close value is set for the RabbitMQ connection.
    attr_accessor :recover_from_connection_close

    def initialize
      @rabbitmq_url = DEFAULT_RABBITMQ_URL
    end

    def validate!
      raise ConnectionNameMissing unless connection_name
    end
  end
end
