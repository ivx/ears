require 'ears/middleware'

module Ears
  module Middlewares
    # A middleware that automatically wraps {Ears::Consumer#work} in an Appsignal transaction.
    class Appsignal < Middleware
      # @param [Hash] opts The options for the middleware.
      # @option opts [String] :transaction_name The name of the Appsignal transaction.
      # @option opts [String] :class_name The name of the class you want to monitor.
      def initialize(opts)
        super()
        @transaction_name = opts.fetch(:transaction_name)
        @class_name = opts.fetch(:class_name)
      end

      def call(delivery_info, metadata, payload, app)
        start_transaction do
          begin
            app.call(delivery_info, metadata, payload)
          rescue => e
            ::Appsignal.set_error(e)
            raise
          end
        end
      end

      private

      attr_reader :transaction_name, :class_name

      def start_transaction(&block)
        ::Appsignal.monitor_transaction(
          transaction_name,
          class: class_name,
          method: 'work',
          queue_start: Time.now.utc,
          &block
        )
      end
    end
  end
end
