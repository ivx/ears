module Ears
  module Testing
    module Matchers
      RSpec::Matchers.define :have_been_published do # rubocop:disable Metrics/BlockLength
        include Ears::Testing::TestHelper

        match do |expected|
          exchange_name = expected[:exchange_name]
          messages = published_messages(exchange_name)

          messages.any? { |message| matches_message?(message, expected) }
        end

        failure_message do |expected|
          "expected a message with #{expected.inspect} to have been published, " \
            "but published were:\n" \
            "#{published_messages(expected[:exchange_name]).map(&:inspect).join("\n")}"
        end

        failure_message_when_negated do |expected|
          matching =
            published_messages(expected[:exchange_name]).select do |m|
              matches_message?(m, expected)
            end
          "expected no message with #{expected.inspect} to have been published, but found:\n" \
            "#{matching.map(&:inspect).join("\n")}"
        end

        def matches_message?(published, expected)
          routing_key = expected[:routing_key]
          data = expected[:data]
          options = expected[:options]

          (!routing_key || published.routing_key == routing_key) &&
            (!data || published.data == data) &&
            (
              !options ||
                options.all? { |key, value| published.options[key] == value }
            )
        end
      end
    end
  end
end
