require 'ears/errors'

module Ears
  # The class representing the global {Ears} configuration.
  class Configuration
    class ConnectionNameMissing < StandardError
    end

    DEFAULT_RABBITMQ_URL = 'amqp://guest:guest@localhost:5672'
    DEFAULT_RECOVERY_ATTEMPTS = 10

    # @return [String] the connection string for RabbitMQ.
    attr_accessor :rabbitmq_url

    # @return [String] the name for the RabbitMQ connection.
    attr_accessor :connection_name

    # @return [Boolean] if the recover_from_connection_close value is set for the RabbitMQ connection.
    attr_accessor :recover_from_connection_close

    # @return [Integer] max number of recovery attempts, nil means forever
    attr_accessor :recovery_attempts

    def initialize
      @rabbitmq_url = DEFAULT_RABBITMQ_URL
      @recovery_attempts = DEFAULT_RECOVERY_ATTEMPTS
    end

    # @return [Proc] that is passed to Bunny’s recovery_attempts_exhausted block. Nil if recovery_attempts is nil.
    def recovery_attempts_exhausted
      return nil unless recovery_attempts

      Proc.new do
        # We need to have this since Bunny’s multi-threading is cumbersome here.
        # Session reconnection seems not to be done in the main thread. If we want to
        # achieve a restart of the app we need to modify the thread behaviour.
        Thread.current.abort_on_exception = true
        raise MaxRecoveryAttemptsExhaustedError
      end
    end

    def validate!
      raise ConnectionNameMissing unless connection_name
    end
  end
end
