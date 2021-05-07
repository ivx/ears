require 'bunny'

module Ears
  class Consumer
    class InvalidReturnError < StandardError
      def initialize(value)
        super(
          "#work must return :ack, :reject or :requeue, received #{value.inspect} instead",
        )
      end
    end

    def self.middlewares
      @middlewares ||= []
    end

    def self.use(middleware, opts = {})
      middlewares << middleware.new(opts)
    end

    def work(delivery_info, metadata, payload)
      raise NotImplementedError
    end

    def process_delivery(delivery_info, metadata, payload)
      self.class.middlewares.reverse.reduce(
        work_proc,
      ) do |next_middleware, middleware|
        nest_middleware(middleware, next_middleware)
      end.call(delivery_info, metadata, payload)
    end

    protected

    def ack
      :ack
    end

    def reject
      :reject
    end

    def requeue
      :requeue
    end

    private

    def work_proc
      ->(delivery_info, metadata, payload) do
        work(delivery_info, metadata, payload).tap do |result|
          verify_result(result)
        end
      end
    end

    def nest_middleware(middleware, next_middleware)
      ->(delivery_info, metadata, payload) do
        middleware.call(delivery_info, metadata, payload, next_middleware)
      end
    end

    def verify_result(result)
      unless %i[ack reject requeue].include?(result)
        raise InvalidReturnError, result
      end
    end
  end
end
