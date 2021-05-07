module Ears
  module Middlewares
    class Appsignal
      attr_reader :transaction_name, :class_name, :method

      def initialize(opts)
        @transaction_name = opts.fetch(:transaction_name)
        @class_name = opts.fetch(:class_name)
      end

      def call(delivery_info, metadata, payload, app)
        ::Appsignal.monitor_transaction(
          transaction_name,
          class: class_name,
          method: 'work',
          queue_start: Time.now.utc,
        ) { app.call(delivery_info, metadata, payload) }
      end
    end
  end
end
