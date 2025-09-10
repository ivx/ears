require 'ears/errors'

module Ears
  class ConfirmationBatch
    def initialize(channel, publisher, config)
      @channel = channel
      @publisher = publisher
      @config = config
      @message_count = 0
    end

    def publish(data, routing_key:, **options)
      if @message_count >= @config.publisher_confirms_batch_size
        raise BatchSizeExceeded,
              "Batch size limit (#{@config.publisher_confirms_batch_size}) exceeded"
      end

      exchange = @publisher.send(:create_exchange, @channel)
      publish_options = @publisher.send(:default_publish_options).merge(options)

      exchange.publish(
        data,
        { routing_key: routing_key }.merge(publish_options),
      )

      @message_count += 1
    end

    def clear
      @message_count = 0
    end
  end
end
