require 'spec_helper'
require 'ears/testing'
require 'ears/publisher'

RSpec.describe 'Ears Testing Integration' do # rubocop:disable RSpec/DescribeClass
  include Ears::Testing::TestHelper

  before do
    Ears.configuration.publisher_max_retries = 0
    mock_ears('events', 'notifications')
  end

  after { ears_reset! }

  it 'captures messages published through Ears::Publisher' do
    publisher = Ears::Publisher.new('events')

    publisher.publish(
      { id: 1, name: 'Test Event' },
      routing_key: 'user.created',
      headers: {
        version: '1.0',
      },
    )

    messages = published_messages('events')
    expect(messages.size).to eq(1)

    message = messages.first
    expect(message.routing_key).to eq('user.created')
    expect(message.data).to eq({ id: 1, name: 'Test Event' })
    expect(message.options[:headers]).to include(version: '1.0')
  end

  it 'captures messages from multiple publishers' do
    events_publisher = Ears::Publisher.new('events')
    notifications_publisher = Ears::Publisher.new('notifications')

    events_publisher.publish({ event: 'login' }, routing_key: 'user.login')
    notifications_publisher.publish(
      { notify: 'welcome' },
      routing_key: 'email.send',
    )
    events_publisher.publish({ event: 'logout' }, routing_key: 'user.logout')

    expect(published_messages('events').size).to eq(2)
    expect(published_messages('notifications').size).to eq(1)
    expect(published_messages.size).to eq(3)
  end

  it 'provides access to the last published message' do
    publisher = Ears::Publisher.new('events')

    publisher.publish({ id: 1 }, routing_key: 'first')
    publisher.publish({ id: 2 }, routing_key: 'second')
    publisher.publish({ id: 3 }, routing_key: 'third')

    expect(last_published_message('events').data).to eq({ id: 3 })
    expect(last_published_message.routing_key).to eq('third')
  end

  it 'allows clearing messages during test' do
    publisher = Ears::Publisher.new('events')

    publisher.publish({ id: 1 }, routing_key: 'test')
    expect(published_messages).not_to be_empty

    clear_published_messages
    expect(published_messages).to be_empty

    publisher.publish({ id: 2 }, routing_key: 'test')
    expect(published_messages.size).to eq(1)
  end

  it 'captures messages with publisher confirms' do
    publisher = Ears::Publisher.new('events')

    publisher.publish_with_confirmation({ id: 1 }, routing_key: 'confirm.test')

    expect(published_messages('events').size).to eq(1)
  end

  it 'raises error when publishing to unmocked exchange' do
    expect {
      Ears::Publisher.new('unmocked').publish(
        { test: 'data' },
        routing_key: 'test',
      )
    }.to raise_error(
      Ears::Testing::UnmockedExchangeError,
      /Exchange 'unmocked' has not been mocked/,
    )
  end
end
