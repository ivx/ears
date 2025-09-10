require 'connection_pool'

module Ears
  # Channel pool management for publishers.
  # Provides thread-safe channel pooling separate from consumer channels.
  # Maintains two separate pools: one for standard publishing and one for confirmed publishing.
  class PublisherChannelPool
    class << self
      # Executes the given block with a channel from the appropriate pool.
      #
      # @param [Boolean] confirms Whether to use a channel with publisher confirms enabled
      # @yieldparam [Bunny::Channel] channel The channel to use for publishing
      # @return [Object] The result of the block
      def with_channel(confirms: false, &)
        # CRITICAL: Preserve fork-safety at the entry point
        reset! if @creator_pid && @creator_pid != Process.pid

        pool = confirms ? confirms_pool : standard_pool
        pool.with(&)
      end

      # Resets both channel pools, forcing new channels to be created.
      # This is useful for connection recovery scenarios.
      #
      # @return [void]
      def reset!
        std_pool = @standard_pool
        cnf_pool = @confirms_pool
        @standard_pool = nil
        @confirms_pool = nil
        @creator_pid = nil

        std_pool&.shutdown(&:close)
        cnf_pool&.shutdown(&:close)
        nil
      end

      # Resets only the confirms channel pool, forcing new confirmed channels to be created.
      # This is useful when confirmation failures occur and channels may have contaminated state.
      #
      # @return [void]
      def reset_confirms_pool!
        cnf_pool = @confirms_pool
        @confirms_pool = nil

        cnf_pool&.shutdown(&:close)
        nil
      end

      private

      def standard_pool
        # CRITICAL: Lazy-init must be thread-safe
        return @standard_pool if @standard_pool

        init_mutex.synchronize do
          # Double-check in case another thread was waiting
          @standard_pool ||=
            begin
              @creator_pid ||= Process.pid
              create_pool(confirms: false)
            end
        end
      end

      def confirms_pool
        # CRITICAL: Lazy-init must be thread-safe
        return @confirms_pool if @confirms_pool

        init_mutex.synchronize do
          # Double-check in case another thread was waiting
          @confirms_pool ||=
            begin
              @creator_pid ||= Process.pid
              create_pool(confirms: true)
            end
        end
      end

      def create_pool(confirms:)
        pool_size = pool_size_for(confirms)

        ConnectionPool.new(
          size: pool_size,
          timeout: Ears.configuration.publisher_pool_timeout,
        ) do
          channel = Ears.connection.create_channel
          channel.confirm_select if confirms
          channel
        end
      end

      def pool_size_for(confirms)
        if confirms &&
             Ears.configuration.respond_to?(:publisher_confirms_pool_size)
          Ears.configuration.publisher_confirms_pool_size
        else
          Ears.configuration.publisher_pool_size
        end
      end

      def init_mutex
        @init_mutex ||= Mutex.new
      end
    end
  end
end
