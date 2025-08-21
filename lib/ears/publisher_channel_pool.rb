require 'connection_pool'

module Ears
  # Channel pool management for publishers.
  # Provides thread-safe channel pooling separate from consumer channels.
  class PublisherChannelPool
    class << self
      # Executes the given block with a channel from the pool.
      #
      # @yieldparam [Bunny::Channel] channel The channel to use for publishing
      # @return [Object] The result of the block
      def with_channel(&)
        channel_pool.with(&)
      end

      # Resets the channel pool, forcing new channels to be created.
      # This is useful for connection recovery scenarios.
      #
      # @return [void]
      def reset!
        pool = @channel_pool
        @channel_pool = nil
        @creator_pid = nil

        pool&.shutdown(&:close)
        nil
      end

      private

      def channel_pool
        # Recreate lazily after a fork
        reset! if @creator_pid && @creator_pid != Process.pid

        return @channel_pool if @channel_pool

        init_mutex.synchronize do
          @channel_pool ||=
            begin
              @creator_pid = Process.pid

              ConnectionPool.new(
                size: Ears.configuration.publisher_pool_size,
                timeout: Ears.configuration.publisher_pool_timeout,
              ) { Ears.connection.create_channel }
            end
        end
      end

      def init_mutex
        @init_mutex ||= Mutex.new
      end
    end
  end
end
