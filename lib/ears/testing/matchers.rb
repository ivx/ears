module Ears
  module Testing
    module Matchers
      RSpec::Matchers.define :have_been_published do
        match do |expected|
          messages = Ears::Testing.message_capture&.all_messages || []

          messages.any? do |message|
            matches_message?(message, expected)
          end
        end

        failure_message do |expected|
          "expected a message with #{expected.inspect} to have been published, " \
            "but published were:\n" \
            "#{Ears::Testing.message_capture&.all_messages&.map(&:inspect)&.join("\n")}"
        end

        failure_message_when_negated do |expected|
          "expected no message with #{expected.inspect} to have been published, but it was."
        end

        def matches_message?(published, expected)
          (!expected[:routing_key] || published.routing_key == expected[:routing_key]) &&
            (!expected[:data]        || published.data == expected[:data]) &&
            (!expected[:options]     || expected[:options].all? { |k, v| published.options[k] == v })
        end
      end
    end
  end
end
