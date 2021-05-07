require 'multi_json'

module Ears
  module Middlewares
    class JSON
      def initialize(_opts); end

      def call(delivery_info, metadata, payload, app)
        parsed_payload = MultiJson.load(payload)
        app.call(delivery_info, metadata, parsed_payload)
      end
    end
  end
end
