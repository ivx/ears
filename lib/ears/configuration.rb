module Ears
  class Configuration
    DEFAULT_RABBITMQ_URL = 'amqp://guest:guest@localhost:5672'

    attr_accessor :rabbitmq_url

    def initialize
      @rabbitmq_url = DEFAULT_RABBITMQ_URL
    end
  end
end
