require 'ears'
require 'ears/testing/test_helper'
require 'ears/testing/message_capture'
require 'ears/testing/publisher_mock'

module Ears
  module Testing
    class << self
      attr_accessor :message_capture

      def configure
        yield(configuration) if block_given?
      end

      def configuration
        @configuration ||= Configuration.new
      end

      def reset!
        @message_capture = nil
        @configuration = nil
      end
    end

    class Configuration
      attr_accessor :max_captured_messages,
                    :auto_cleanup,
                    :strict_exchange_mocking

      def initialize
        @max_captured_messages = 1000
        @auto_cleanup = true
        @strict_exchange_mocking = true
      end
    end
  end
end
