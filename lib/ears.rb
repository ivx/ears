require 'bunny'
require 'ears/consumer'
require 'ears/setup'
require 'ears/version'

module Ears
  class Error < StandardError
  end

  class << self
    def connection
      @connection ||= Bunny.new.tap { |conn| conn.start }
    end

    def channel
      Thread.current[:ears_channel] ||= connection.create_channel
    end

    def setup(&block)
      Ears::Setup.new.instance_eval(&block)
    end

    def run!
      running = true
      Signal.trap('INT') { running = false }
      Signal.trap('TERM') { running = false }
      sleep 1 while running
    end

    def reset!
      @connection = nil
      Thread.current[:ears_channel] = nil
    end
  end
end
