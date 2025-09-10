require 'bunny'

module Ears
  # A handler for retries and connection recovery when publishing messages.
  class PublisherRetryHandler
    # Exception for publishing to a stale/closed channel
    class PublishToStaleChannelError < StandardError
    end

    # Connection errors that should trigger retries
    CONNECTION_ERRORS = [
      PublishToStaleChannelError,
      Bunny::ChannelAlreadyClosed,
      Bunny::ConnectionClosedError,
      Bunny::ConnectionForced,
      Bunny::NetworkFailure,
      Bunny::TCPConnectionFailed,
      IOError,
      Timeout::Error,
    ].freeze

    # Confirmation errors should NOT be retried - they indicate the message
    # was published but confirmation failed, so retrying would duplicate the message
    NON_RETRYABLE_ERRORS = [
      PublishConfirmationTimeout,
      PublishNacked,
      BatchSizeExceeded,
    ].freeze

    def initialize(config, logger)
      @config = config
      @logger = logger
    end

    def run(&block)
      attempt = 1
      begin
        block.call
      rescue *NON_RETRYABLE_ERRORS => e
        # Don't retry confirmation errors - they indicate the message was published
        # but confirmation failed. Retrying would duplicate the message.
        raise e
      rescue *CONNECTION_ERRORS => e
        attempt = handle_connection_error(e, attempt) # rubocop:disable Lint/UselessAssignment
        retry
      rescue StandardError => e
        attempt = handle_standard_error(e, attempt)
        retry
      end
    end

    private

    attr_reader :config, :logger

    def handle_connection_error(error, attempt)
      raise(error) unless retry?(error, attempt)

      wait_for_connection(error)
      logger.info('Resetting channel pool after connection recovery')
      PublisherChannelPool.reset!

      attempt + 1
    end

    def handle_standard_error(error, attempt)
      raise(error) unless retry?(error, attempt)

      sleep(retry_backoff_delay(attempt)) if attempt > 1
      attempt + 1
    end

    def retry?(error, attempt)
      logger.info(
        "Trying to recover from publish error. Attempt #{attempt}: #{error.class}: #{error.message}",
      )

      if attempt > config.publisher_max_retries
        logger.warn(
          "Connection attempts exhausted, giving up: #{error.class}: #{error.message}",
        )
        return false
      end

      true
    end

    def wait_for_connection(original_error)
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
