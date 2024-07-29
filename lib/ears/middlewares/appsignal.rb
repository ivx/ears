require 'ears/middleware'

module Ears
  module Middlewares
    # A middleware that automatically wraps {Ears::Consumer#work} in an Appsignal transaction.
    class Appsignal < Middleware
      # @param [Hash] opts The options for the middleware.
      # @option opts [String] :class_name The name of the class you want to monitor.
      # @option opts [String] :namespace ('background') The namespace in which the action should appear.
      def initialize(opts)
        super()
        @class_name = opts.fetch(:class_name)
        @namespace = opts.fetch(:namespace, 'background')
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

      attr_reader :namespace, :class_name

      def start_transaction(&block)
        ::Appsignal.monitor(
          namespace: namespace,
          action: "#{class_name}#work",
          &block
        )
      end
    end
  end
end
