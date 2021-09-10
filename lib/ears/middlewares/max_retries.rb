require 'ears/middleware'

module Ears
  module Middlewares
    # A middleware that automatically puts messages on an error queue when the specified number of retries are exceeded.
    class MaxRetries < Middleware
      # @param [Hash] opts The options for the middleware.
      # @option opts [Integer] :retries The number of retries before the message is sent to the error queue.
      # @option opts [String] :error_queue The name of the queue where messages should be sent to when the max retries are reached.
      def initialize(opts)
        super()
        @retries = opts.fetch(:retries)
        @error_queue = opts.fetch(:error_queue)
      end

      def call(delivery_info, metadata, payload, app)
        return handle_exceeded(payload) if retries_exceeded?(metadata)
        app.call(delivery_info, metadata, payload)
      end

      private

      attr_reader :retries, :error_queue

      def handle_exceeded(payload)
        Bunny::Exchange
          .default(Ears.channel)
          .publish(payload, routing_key: error_queue)
        :ack
      end

      def retries_exceeded?(metadata)
        rejected_deaths =
          metadata
            .headers
            .fetch('x-death', [])
            .select { |death| death['reason'] == 'rejected' }

        return false unless rejected_deaths.any?

        retry_count = rejected_deaths.map { |death| death['count'] }.max
        retry_count > @retries
      end
    end
  end
end
