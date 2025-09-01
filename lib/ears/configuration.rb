require 'ears/errors'

module Ears
  # The class representing the global {Ears} configuration.
  class Configuration
    class ConnectionNameMissing < StandardError
    end

    DEFAULT_RABBITMQ_URL = 'amqp://guest:guest@localhost:5672'
    DEFAULT_RECOVERY_ATTEMPTS = 10
    DEFAULT_PUBLISHER_POOL_SIZE = 32
    DEFAULT_PUBLISHER_POOL_TIMEOUT = 2
    DEFAULT_PUBLISHER_CONNECTION_ATTEMPTS = 30
    DEFAULT_PUBLISHER_CONNECTION_BASE_DELAY = 1
    DEFAULT_PUBLISHER_CONNECTION_BACKOFF_FACTOR = 1.5
    DEFAULT_PUBLISHER_MAX_RETRIES = 3
    DEFAULT_PUBLISHER_RETRY_BASE_DELAY = 0.1
    DEFAULT_PUBLISHER_RETRY_BACKOFF_FACTOR = 2

    # @return [String] the connection string for RabbitMQ.
    attr_accessor :rabbitmq_url

    # @return [String] the name for the RabbitMQ connection.
    attr_accessor :connection_name

    # @return [Boolean] if the recover_from_connection_close value is set for the RabbitMQ connection.
    attr_accessor :recover_from_connection_close

    # @return [Integer] max number of recovery attempts, nil means forever
    attr_accessor :recovery_attempts

    # @return [Integer] the size of the publisher channel pool
    attr_accessor :publisher_pool_size

    # @return [Integer] the timeout in seconds for acquiring a channel from the publisher pool
    attr_accessor :publisher_pool_timeout

    # @return [Integer] the number of connection attempts for the publisher
    attr_accessor :publisher_connection_attempts

    # @return [Float] the base delay in seconds between connection attempts
    attr_accessor :publisher_connection_base_delay

    # @return [Float] the backoff factor for exponential connection delays
    attr_accessor :publisher_connection_backoff_factor

    # @return [Integer] the maximum number of retries for failed publish attempts
    attr_accessor :publisher_max_retries

    # @return [Float] the base delay in seconds between retry attempts
    attr_accessor :publisher_retry_base_delay

    # @return [Float] the backoff factor for exponential retry delays
    attr_accessor :publisher_retry_backoff_factor

    def initialize
      @rabbitmq_url = DEFAULT_RABBITMQ_URL
      @recovery_attempts = DEFAULT_RECOVERY_ATTEMPTS
      @publisher_pool_size = DEFAULT_PUBLISHER_POOL_SIZE
      @publisher_pool_timeout = DEFAULT_PUBLISHER_POOL_TIMEOUT
      @publisher_connection_attempts = DEFAULT_PUBLISHER_CONNECTION_ATTEMPTS
      @publisher_connection_base_delay = DEFAULT_PUBLISHER_CONNECTION_BASE_DELAY
      @publisher_connection_backoff_factor =
        DEFAULT_PUBLISHER_CONNECTION_BACKOFF_FACTOR
      @publisher_max_retries = DEFAULT_PUBLISHER_MAX_RETRIES
      @publisher_retry_base_delay = DEFAULT_PUBLISHER_RETRY_BASE_DELAY
      @publisher_retry_backoff_factor = DEFAULT_PUBLISHER_RETRY_BACKOFF_FACTOR
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
