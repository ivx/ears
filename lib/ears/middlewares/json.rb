require 'ears/middleware'
require 'multi_json'

module Ears
  module Middlewares
    # A middleware that automatically parses your JSON payload.
    class JSON < Middleware
      # @param [Hash] opts The options for the middleware.
      # @option opts [Proc] :on_error A Proc to be called when an error occurs during processing
      # @option opts [Boolean] :symbolize_keys (true) Whether to symbolize the keys of your payload.
      def initialize(opts = {})
        super()
        @on_error = opts.fetch(:on_error)
        @symbolize_keys = opts.fetch(:symbolize_keys, true)
      end

      def call(delivery_info, metadata, payload, app)
        begin
          parsed_payload =
            MultiJson.load(payload, symbolize_keys: symbolize_keys)
        rescue => e
          return on_error.call(e)
        end

        app.call(delivery_info, metadata, parsed_payload)
      end

      private

      attr_reader :symbolize_keys, :on_error
    end
  end
end
