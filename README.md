# Ears

`Ears` is a small, simple library for writing RabbitMQ consumers and publishers.

[![CodeQL](https://github.com/ivx/ears/actions/workflows/codeql.yml/badge.svg)](https://github.com/ivx/ears/actions/workflows/codeql.yml)

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'ears'
```

And then execute:

    $ bundle install

Or install it yourself as:

    $ gem install ears

## Usage

### Publishing Messages

`Ears` provides a thread-safe publisher for sending messages to RabbitMQ exchanges with automatic retry and connection recovery capabilities.

#### Basic Publisher Usage

To publish messages, create an `Ears::Publisher` instance and call `publish`:

```ruby
require 'ears'

# Configure Ears (same configuration is shared by consumers and publishers)
Ears.configure do |config|
  config.rabbitmq_url = 'amqp://user:password@myrmq:5672'
  config.connection_name = 'My Publisher'
end

# Create a publisher for a topic exchange
publisher = Ears::Publisher.new('my_exchange', :topic, durable: true)

# Publish a message
data = { user_id: 123, action: 'login', timestamp: Time.now.iso8601 }
publisher.publish(data, routing_key: 'user.login')
```

#### Exchange Types and Options

Publishers support all RabbitMQ exchange types:

```ruby
# Topic exchange (default)
topic_publisher = Ears::Publisher.new('events', :topic)

# Direct exchange
direct_publisher = Ears::Publisher.new('commands', :direct)

# Fanout exchange
fanout_publisher = Ears::Publisher.new('broadcasts', :fanout)

# Headers exchange
headers_publisher = Ears::Publisher.new('complex_routing', :headers)

# Custom exchange options
publisher =
  Ears::Publisher.new(
    'my_exchange',
    :topic,
    durable: true,
    auto_delete: false,
    arguments: {
      'x-message-ttl' => 60_000,
    },
  )
```

#### Message Options

The `publish` method accepts various message options:

```ruby
publisher.publish(
  { message: 'Hello World' },
  routing_key: 'greeting.hello',
  persistent: true, # Persist message to disk (default: true)
  headers: {
    version: '1.0',
  }, # Custom headers
  timestamp: Time.now.to_i, # Message timestamp (default: current time)
  message_id: SecureRandom.uuid, # Unique message identifier
  correlation_id: 'abc-123', # Correlation ID for request/response patterns
  reply_to: 'response_queue', # Queue for responses
  expiration: '60000', # Message TTL in milliseconds
  priority: 5, # Message priority (0-9)
  type: 'user_event', # Message type
  app_id: 'my_application', # Application identifier
  user_id: 'system', # User identifier (verified by RabbitMQ)
)
```

#### Thread-Safe Publishing

Publishers use a connection pool for thread-safe operation, making them suitable for concurrent use:

```ruby
# Single publisher can be safely used across multiple threads
publisher = Ears::Publisher.new('events', :topic)

# Example with multiple threads
threads =
  10.times.map do |i|
    Thread.new do
      100.times do |j|
        publisher.publish({ thread: i, message: j }, routing_key: "thread.#{i}")
      end
    end
  end

threads.each(&:join)
```

#### Publisher Configuration

Publisher behavior can be fine-tuned through configuration options:

```ruby
Ears.configure do |config|
  # Connection settings
  config.rabbitmq_url = 'amqp://user:password@myrmq:5672'
  config.connection_name = 'My Application'

  # Publisher-specific settings
  config.publisher_pool_size = 32 # Channel pool size (default: 32)
  config.publisher_pool_timeout = 2 # Pool checkout timeout in seconds (default: 2)

  # Connection retry settings
  config.publisher_connection_attempts = 30 # Connection retry attempts (default: 30)
  config.publisher_connection_base_delay = 1 # Base delay between connection attempts (default: 1s)
  config.publisher_connection_backoff_factor = 1.5 # Connection backoff multiplier (default: 1.5)

  # Publish retry settings
  config.publisher_max_retries = 3 # Max publish retry attempts (default: 3)
  config.publisher_retry_base_delay = 0.1 # Base delay between publish retries (default: 0.1s)
  config.publisher_retry_backoff_factor = 2 # Publish retry backoff multiplier (default: 2)
end
```

#### Fault Tolerance and Recovery

Publishers automatically handle connection failures and provide several recovery mechanisms:

##### Automatic Retry with Exponential Backoff

```ruby
# Publishers automatically retry failed operations
publisher = Ears::Publisher.new('events', :topic)

# This will automatically retry with exponential backoff if the connection fails
publisher.publish({ event: 'user_signup' }, routing_key: 'user.signup')
```

##### Manual Recovery

If you need to manually reset the connection pool (e.g., after detecting connection issues):

```ruby
publisher = Ears::Publisher.new('events', :topic)

# Reset the channel pool to force new connections
publisher.reset!

# Subsequent publishes will use fresh channels
publisher.publish({ event: 'recovery_test' }, routing_key: 'system.recovery')
```

##### Error Handling

Publishers raise specific exceptions that you can handle:

```ruby
require 'ears'

publisher = Ears::Publisher.new('events', :topic)

begin
  publisher.publish({ data: 'test' }, routing_key: 'test.message')
rescue Ears::PublisherRetryHandler::PublishError => e
  # Handle publish failures (after all retries exhausted)
  logger.error "Failed to publish message: #{e.message}"
  # Consider queuing message for later retry or alerting
rescue => e
  # Handle other unexpected errors
  logger.error "Unexpected error: #{e.message}"
end
```

### Publisher Confirms

#### Basic Usage

For guaranteed message delivery, use `publish_with_confirmation` which waits for broker acknowledgment:

```ruby
publisher = Ears::Publisher.new('events', :topic)

# Publish with confirmation - blocks until broker acknowledges
publisher.publish_with_confirmation(
  { user_id: 123, action: 'payment_processed' },
  routing_key: 'payment.processed',
)
```

#### Configuration

Publisher confirms use a separate channel pool with configurable settings:

```ruby
Ears.configure do |config|
  # Confirms-specific channel pool size (default: 32)
  config.publisher_confirms_pool_size = 32

  # Timeout for waiting for confirms in seconds (default: 5.0)
  config.publisher_confirms_timeout = 5.0

  # Cleanup timeout after confirmation failure (default: 1.0)
  config.publisher_confirms_cleanup_timeout = 1.0
end
```

#### Error Handling

Publisher confirms raise specific exceptions that are NOT automatically retried:

```ruby
begin
  publisher.publish_with_confirmation(data, routing_key: 'important.event')
rescue Ears::PublishConfirmationTimeout => e
  # Message may or may not have reached broker
  logger.error "Confirmation timed out: #{e.message}"
rescue Ears::PublishNacked => e
  # Broker explicitly rejected the message
  logger.error "Message was nacked: #{e.message}"
end
```

**Note:** Unlike regular publishing, confirmation errors are not retried to avoid message duplication.

### Basic consumer usage

First, you should configure `Ears`.

```ruby
require 'ears'

Ears.configure do |config|
  config.rabbitmq_url = 'amqp://user:password@myrmq:5672'
  config.connection_name = 'My Consumer'
  config.recover_from_connection_close = false # optional configuration, defaults to true if not set
  config.recovery_attempts = 3 # optional configuration, defaults to 10, Bunny::Session would have been nil

  # Publisher configuration (optional)
  config.publisher_pool_size = 32 # Thread pool size for publishers (default: 32)
  config.publisher_pool_timeout = 2 # Timeout for pool checkout in seconds (default: 2)
  config.publisher_connection_attempts = 30 # Connection retry attempts (default: 30)
  config.publisher_connection_base_delay = 1 # Base delay between connection attempts in seconds (default: 1)
  config.publisher_connection_backoff_factor = 1.5 # Connection retry backoff multiplier (default: 1.5)
  config.publisher_max_retries = 3 # Max publish retry attempts (default: 3)
  config.publisher_retry_base_delay = 0.1 # Base delay between publish retries in seconds (default: 0.1)
  config.publisher_retry_backoff_factor = 2 # Publish retry backoff multiplier (default: 2)
end
```

_Note_: `connection_name` is a mandatory setting!

Next, you can define your exchanges, queues, and consumers in 2 ways:

#### 1. consumer specific configuration method (recommended)

1. Pass your consumer classes to `Ears.setup`:

```ruby
Ears.setup do
  Ears.setup_consumers(Consumer1, Consumer2, ...)
end
```

2. Implement your consumers by subclassing `Ears::Consumer`. and call the configure method.

```ruby
class Consumer1 < Ears::Consumer
  configure(
    queue: 'queue_name',
    exchange: 'exchange',
    routing_keys: %w[routing_key1 routing_key2],
    retry_queue: true, # optional configuration, defaults to false, Adds a retry queue
    error_queue: true, # optional configuration, defaults to false, Adds an error queue
  )
  def work(delivery_info, metadata, payload)
    message = JSON.parse(payload)
    do_stuff(message)

    ack
  end
end
```

#### 2. Generic configuration method

```ruby
Ears.setup do
  # define a durable topic exchange
  my_exchange = exchange('my_exchange', :topic, durable: true)

  # define a queue
  my_queue = queue('my_queue', durable: true)

  # bind your queue to the exchange
  my_queue.bind(my_exchange, routing_key: 'my.routing.key')

  # define a consumer that handles messages for that queue
  consumer(my_queue, MyConsumer)
end
```

Finally, you need to implement `MyConsumer` by subclassing `Ears::Consumer`. and call the configure method.

```ruby
class MyConsumer < Ears::Consumer
  def work(delivery_info, metadata, payload)
    message = JSON.parse(payload)
    do_stuff(message)

    ack
  end
end
```

### Run your consumers

Note: Be prepared that unhandled errors will be reraised. So, take care of cleanup work.

```ruby
begin
  Ears.run!
ensure
  # all your cleanup work goes here...
end
```

At the end of the `#work` method, you must always return `ack`, `reject`, or `requeue` to signal what should be done with the message.

### Middlewares

`Ears` supports middlewares that you can use for recurring tasks that you don't always want to reimplement. It comes with some built-in middlewares:

- `Ears::JSON` for automatically parsing JSON payloads
- `Ears::Appsignal` for automatically wrapping `#work` in an Appsignal transaction

You can use a middleware by just calling `use` with the middleware you want to register in your consumer.

```ruby
require 'ears/middlewares/json'

class MyConsumer < Ears::Consumer
  # register the JSON middleware and don't symbolize keys (this can be omitted, the default is true)
  # and nack the message on parsing error. This defaults to Proc.new { :reject }.
  use Ears::Middlewares::JSON,
      on_error: Proc.new { :nack },
      symbolize_keys: false

  def work(delivery_info, metadata, payload)
    return ack unless payload['data'].nil? # this now just works
  end
end
```

If you want to implement your own middleware, just subclass `Ears::Middleware` and implement `#call` (and if you need it `#initialize`).

```ruby
class MyMiddleware < Ears::Middleware
  def initialize(opts = {})
    @my_option = opts.fetch(:my_option, nil)
  end

  def call(delivery_info, metadata, payload, app)
    do_stuff

    # always call the next middleware in the chain or your consumer will never be called
    app.call(delivery_info, metadata, payload)
  end
end
```

### Multiple threads

If you need to handle a lot of messages, you might want to have multiple instances of the same consumer all working on a dedicated thread. This is supported out of the box. You just have to define how many consumers you want when calling `consumer` in `Ears.setup`.

```ruby
Ears.setup do
  my_exchange = exchange('my_exchange', :topic, durable: true)
  my_queue = queue('my_queue', durable: true)
  my_queue.bind(my_exchange, routing_key: 'my.routing.key')

  # this will instantiate MyConsumer 10 times and run every instance on a dedicated thread
  consumer(my_queue, MyConsumer, 10)
end
```

It may also be interesting for you to increase the prefetch amount. The default prefetch amount is 1, but if you have a lot of very small, fast to process messages, a higher prefetch is a good idea. Just set it when defining your consumer.

```ruby
Ears.setup do
  my_exchange = exchange('my_exchange', :topic, durable: true)
  my_queue = queue('my_queue', durable: true)
  my_queue.bind(my_exchange, routing_key: 'my.routing.key')

  # this will instantiate one consumer but with a prefetch value of 10
  consumer(my_queue, MyConsumer, 1, prefetch: 10)
end
```

### Setting arbitrary exchange/queue parameters

If you need some custom arguments on your exchange or queue, you can just pass these to `queue` or `exchange` inside `Ears.setup`. These are then just passed on to `Bunny::Queue` and `Bunny::Exchange`.

```ruby
Ears.setup do
  my_queue =
    queue('my_queue', durable: true, arguments: { 'x-message-ttl' => 10_000 })
end
```

### Implementing a retrying queue

Sometimes you want to automatically retry processing a message, in case it just failed due to temporary problems. In that case, you can set the `retry_queue` and `retry_delay` parameters when creating the queue OR pass it to the configure method in your consumer.

```ruby
class MyConsumer < Ears::Consumer
  configure(
    queue: 'queue_name',
    exchange: 'exchange',
    routing_keys: %w[routing_key1 routing_key2],
    retry_queue: true,
  )
  def work(delivery_info, metadata, payload)
    message = JSON.parse(payload)
    do_stuff(message)

    ack
  end
end
```

```ruby
my_queue =
  queue('my_queue', durable: true, retry_queue: true, retry_delay: 5000)
```

This will automatically create a queue named `my_queue.retry` and use the arguments `x-dead-letter-exchange` and `x-dead-letter-routing-key` to route rejected messages to it. When routed to the retry queue, messages will wait there for the number of milliseconds specified in `retry_delay`, after which they will be redelivered to the original queue. **Note that this will not automatically catch unhandled errors. You still have to catch any errors yourself and reject your message manually for the retry mechanism to work.**

This will happen indefinitely, so if you want to bail out of this cycle at some point, it is best to use the `error_queue` option to create an error queue and then use the `MaxRetries` middleware to route messages to this error queue after a certain amount of retries.

### Implementing an error queue

You can set the `error_queue` parameter to automatically create an error queue, or add it to the configure method in your consumer.

```ruby
class MyConsumer < Ears::Consumer
  configure(
    queue: 'queue_name',
    exchange: 'exchange',
    routing_keys: %w[routing_key1 routing_key2],
    error_queue: true,
  )
  def work(delivery_info, metadata, payload)
    message = JSON.parse(payload)
    do_stuff(message)

    ack
  end
end
```

```ruby
my_queue =
  queue(
    'my_queue',
    durable: true,
    retry_queue: true,
    retry_delay: 5000,
    error_queue: true,
  )
```

This will automatically create a queue named `my_queue.error`. It does not have any special properties, the helper's main purpose is to enforce naming conventions. In your consumer, you should then use the `MaxRetries` middleware to route messages to the error queue after a certain amount of retries.

```ruby
class MyConsumer < Ears::Consumer
  use Ears::Middlewares::MaxRetries, retries: 3, error_queue: 'my_queue.error'

  def work(delivery_info, metadata, payload)
    # ...
  end
end
```

This will automatically route messages to `my_queue.error` after they have been re-tried three times. This prevents you from infinitely retrying a faulty message.

### Stopping any running consumers

When you are running Ears in a non-blocking way (e.g. in a Thread), it might be cumbersome to remove the running consumers without restarting the whole app.

For this use case, there is a stop! method:

```ruby
Ears.stop!
```

It will close and reset the current Bunny connection, leading to all consumers being shut down. Also, it will reset the channel.

### Complete Example: Consumer and Publisher

Here's a complete example showing both consumer and publisher usage:

```ruby
require 'ears'

# Shared configuration
Ears.configure do |config|
  config.rabbitmq_url = 'amqp://guest:guest@localhost:5672'
  config.connection_name = 'Order Processing Service'
  config.publisher_pool_size = 16
end

# Consumer that processes orders and publishes events
class OrderProcessor < Ears::Consumer
  configure(
    queue: 'orders',
    exchange: 'ecommerce',
    routing_keys: %w[order.created order.updated],
    retry_queue: true,
    error_queue: true,
  )

  def initialize
    super
    @event_publisher = Ears::Publisher.new('events', :topic, durable: true)
  end

  def work(delivery_info, metadata, payload)
    order = JSON.parse(payload)

    # Process the order
    process_order(order)

    # Publish success event
    @event_publisher.publish(
      {
        order_id: order['id'],
        status: 'processed',
        processed_at: Time.now.iso8601,
      },
      routing_key: 'order.processed',
    )

    ack
  rescue => error
    # Publish error event
    @event_publisher.publish(
      {
        order_id: order&.dig('id'),
        error: error.message,
        failed_at: Time.now.iso8601,
      },
      routing_key: 'order.failed',
    )

    reject # Send to error queue
  end

  private

  def process_order(order)
    # Order processing logic here
    sleep(0.1) # Simulate processing time
  end
end

# Setup and run
Ears.setup { Ears.setup_consumers(OrderProcessor) }

begin
  Ears.run!
ensure
  # Cleanup code here
end
```

## Testing

Ears provides testing helpers to easily test your message publishing without connecting to RabbitMQ.

### Basic Setup

Include the test helper in your RSpec tests and mock the exchanges you want to test:

```ruby
require 'ears/testing'

RSpec.describe MyService do
  include Ears::Testing::TestHelper

  before do
    # Mock exchanges that your code will publish to
    mock_ears('events', 'notifications')
  end

  after do
    # Clean up mocks and captured messages
    ears_reset!
  end
end
```

### Capturing and Inspecting Messages

Use the helper methods to inspect published messages:

```ruby
it 'publishes user creation event' do
  service = UserService.new
  service.create_user(name: 'John', email: 'john@example.com')

  # Get all messages published to 'events' exchange
  messages = published_messages('events')
  expect(messages.size).to eq(1)

  # Inspect the message
  message = messages.first
  expect(message.routing_key).to eq('user.created')
  expect(message.data).to include(name: 'John')
  expect(message.options[:headers]).to include(version: '1.0')
end
```

### Available Helper Methods

- `published_messages(exchange_name = nil)` - Get messages for a specific exchange or all messages
- `last_published_message(exchange_name = nil)` - Get the most recent message
- `clear_published_messages` - Clear captured messages during a test

### Message Properties

Each captured message has the following properties:

- `exchange_name` - Name of the exchange
- `routing_key` - Message routing key
- `data` - The message payload
- `options` - Publishing options (headers, persistent, etc.)
- `timestamp` - When the message was captured
- `thread_id` - Thread that published the message

### Custom RSpec Matcher: `have_been_published`

To make tests more expressive, Ears provides a custom RSpec matcher that allows you to easily assert that a specific message was published to a mocked exchange.

#### Usage

Include the matcher by requiring `ears/testing` in your RSpec tests and including the helper module:

```ruby
require 'ears/testing'

RSpec.describe MyPublisher do
  include Ears::Testing::TestHelper

  before { mock_ears('events') }
  after { ears_reset! }

  it 'publishes a user.created message' do
    publisher = Ears::Publisher.new('events', :topic)
    publisher.publish({ user_id: 1 }, routing_key: 'user.created')

    expect(
      exchange_name: 'events',
      routing_key: 'user.created',
      data: {
        user_id: 1,
      },
    ).to have_been_published
  end

  # also works with negative assertions
  it 'does not publish a user.deleted message' do
    publisher = Ears::Publisher.new('events', :topic)
    publisher.publish({ user_id: 1 }, routing_key: 'user.created')

    expect(
      exchange_name: 'events',
      routing_key: 'user.deleted',
      data: {
        user_id: 1,
      },
    ).not_to have_been_published
  end
end
```

#### Supported Keys

You can match on any or all of the following attributes:

| Key              | Description                                    | Example                                             |
| ---------------- | ---------------------------------------------- | --------------------------------------------------- |
| `:exchange_name` | The exchange where the message was published   | `'events'`                                          |
| `:routing_key`   | The routing key used for the message           | `'user.created'`                                    |
| `:data`          | The message payload (exact match)              | `{ user_id: 1 }`                                    |
| `:options`       | Message options such as headers or persistence | `{ persistent: true, headers: { version: '1.0' } }` |

If a key is omitted, it will not be checked — allowing partial matches (for example, matching only on `exchange_name` and `routing_key`).

#### Example: Matching with Options

> **Note:** When matching `:options`, you only need to specify the options you want to verify — the matcher will ignore any additional options present in the published message.

```ruby
expect(
  exchange_name: 'events',
  routing_key: 'user.created',
  data: {
    id: 42,
    name: 'Alice',
  },
  options: {
    persistent: true,
  },
).to have_been_published
```

### Error Handling

By default, publishing to unmocked exchanges raises an error:

```ruby
it 'raises error for unmocked exchanges' do
  publisher = Ears::Publisher.new('unmocked_exchange')

  expect {
    publisher.publish({ data: 'test' }, routing_key: 'test')
  }.to raise_error(Ears::Testing::UnmockedExchangeError)
end
```

### Complete Example

```ruby
require 'ears/testing'

RSpec.describe OrderProcessor do
  include Ears::Testing::TestHelper

  before { mock_ears('events', 'notifications') }
  after { ears_reset! }

  it 'publishes events when processing order' do
    processor = OrderProcessor.new
    order = { id: 123, items: ['item1'], total: 99.99 }

    processor.process(order)

    # Check event was published
    events = published_messages('events')
    expect(events.size).to eq(1)
    expect(events.first.routing_key).to eq('order.processed')
    expect(events.first.data[:order_id]).to eq(123)

    # Check notification was sent
    notifications = published_messages('notifications')
    expect(notifications.size).to eq(1)
    expect(notifications.first.routing_key).to eq('email.order_confirmation')
  end
end
```

## Documentation

If you need more in-depth information, look at [our API documentation](https://www.rubydoc.info/gems/ears).

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/ivx/ears. This project is intended to be a safe, welcoming space for collaboration, and contributors are expected to adhere to the [code of conduct](https://github.com/ivx/ears/blob/main/CODE_OF_CONDUCT.md).

## License

The gem is available as open-source under the terms of the [MIT License](https://opensource.org/licenses/MIT).

## Code of Conduct

Everyone interacting in the Ears project's codebases, issue trackers, chat rooms, and mailing lists is expected to follow the [code of conduct](https://github.com/ivx/ears/blob/main/CODE_OF_CONDUCT.md).
