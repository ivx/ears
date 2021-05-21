module Ears
  # The class representing the global {Ears} configuration.
  class Configuration
    DEFAULT_RABBITMQ_URL = 'amqp://guest:guest@localhost:5672'

    # @return [String] the connection string for RabbitMQ.
    attr_accessor :rabbitmq_url

    def initialize
      @rabbitmq_url = DEFAULT_RABBITMQ_URL
    end
  end
end
