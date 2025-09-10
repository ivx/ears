require 'timeout'
require 'ears/errors'

module Ears
  module PublisherConfirmationSupport
    private

    def publish_with_confirms(
      data:,
      routing_key:,
      publish_options:,
      wait_for_confirm: false,
      timeout: nil
    )
      validate_connection!

      PublisherChannelPool.with_channel(confirms: true) do |channel|
        exchange = create_exchange(channel)

        exchange.publish(
          data,
          { routing_key: routing_key }.merge(publish_options),
        )

        if wait_for_confirm
          unless wait_for_confirms_with_timeout(channel, timeout)
            handle_confirmation_failure(channel, timeout)
          end
        end
      end
    end

    def wait_for_confirms_with_timeout(channel, timeout)
      begin
        Timeout.timeout(timeout) { return channel.wait_for_confirms }
      rescue Timeout::Error
        false
      end
    end

    def handle_confirmation_failure(channel, timeout)
      if channel.nacked_set && !channel.nacked_set.empty?
        raise PublishNacked, 'Message was nacked by broker'
      else
        raise PublishConfirmationTimeout,
              "Confirmation timeout after #{timeout}s"
      end
    end
  end
end
