require 'multi_json'

module Ears
  module Middlewares
    class JSON
      attr_reader :symbolize_keys

      def initialize(opts = {})
        @symbolize_keys = opts.fetch(:symbolize_keys, true)
      end

      def call(delivery_info, metadata, payload, app)
        parsed_payload = MultiJson.load(payload, symbolize_keys: symbolize_keys)
        app.call(delivery_info, metadata, parsed_payload)
      end
    end
  end
end
