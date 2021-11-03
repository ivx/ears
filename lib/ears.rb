require 'bunny'
require 'ears/configuration'
require 'ears/consumer'
require 'ears/middleware'
require 'ears/setup'
require 'ears/version'

module Ears
  class << self
    # The global configuration for Ears.
    #
    # @return [Ears::Configuration]
    def configuration
      @configuration ||= Ears::Configuration.new
    end

    # Yields the global configuration instance so you can modify it.
    # @yieldparam configuration [Ears::Configuration] The global configuration instance.
    def configure
      yield(configuration)
    end

    # The global RabbitMQ connection used by Ears.
    #
    # @return [Bunny::Session]
    def connection
      @connection ||=
        Bunny.new(configuration.rabbitmq_url).tap { |conn| conn.start }
    end

    # The channel for the current thread.
    #
    # @return [Bunny::Channel]
    def channel
      Thread.current[:ears_channel] ||=
        connection
          .create_channel(nil, 1, true)
          .tap do |channel|
            channel.prefetch(1)
            channel.on_uncaught_exception { |error| Ears.error!(error) }
          end
    end

    # Used to set up your exchanges, queues and consumers. See {Ears::Setup} for implementation details.
    def setup(&block)
      Ears::Setup.new.instance_eval(&block)
    end

    # Blocks the calling thread until +SIGTERM+ or +SIGINT+ is received.
    # Used to keep the process alive while processing messages.
    def run!
      running = true
      Signal.trap('INT') { running = false }
      Signal.trap('TERM') { running = false }
      sleep 1 while running && @error.nil?
      raise @error if @error
    end

    # Signals that an uncaught error has occurred and the process should be stopped.
    #
    # @param [Exception] error The unhandled error that occurred.
    def error!(error)
      puts(error.full_message)
      @error = error
    end

    # Used internally for testing.
    def reset!
      @connection = nil
      Thread.current[:ears_channel] = nil
    end
  end
end
