require 'ears/middleware'
require 'multi_json'

module Ears
  module Middlewares
    # A middleware that automatically parses your JSON payload.
    class JSON < Middleware
      # @param [Hash] opts The options for the middleware.
      # @option opts [Boolean] :symbolize_keys Whether to symbolize the keys of your payload.
      def initialize(opts = {})
        super()
        @symbolize_keys = opts.fetch(:symbolize_keys, true)
      end

      def call(delivery_info, metadata, payload, app)
        parsed_payload = MultiJson.load(payload, symbolize_keys: symbolize_keys)
        app.call(delivery_info, metadata, parsed_payload)
      end

      private

      attr_reader :symbolize_keys
    end
  end
end
