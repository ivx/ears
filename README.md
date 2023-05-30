# Ears

`Ears` is a small, simple library for writing RabbitMQ consumers.

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

### Basic usage

First, you should configure `Ears`.

```ruby
require 'ears'

Ears.configure do |config|
  config.rabbitmq_url = 'amqp://user:password@myrmq:5672'
  config.connection_name = 'My Consumer'
  config.recover_from_connection_close = false # optional configuration, defaults to true if not set
  config.recovery_attempts = 3 # optional configuration, defaults to 10, Bunny::Session would have been nil
end
```

_Note_: `connection_name` is a mandatory setting!

Next, define your exchanges, queues, and consumers by calling `Ears.setup`.

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

Finally, you need to implement `MyConsumer` by subclassing `Ears::Consumer`.

```ruby
class MyConsumer < Ears::Consumer
  def work(delivery_info, metadata, payload)
    message = JSON.parse(payload)
    do_stuff(message)

    ack
  end
end
```

And, do not forget to run it. Be prepared that unhandled errors will be reraised. So, take care of cleanup work.

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

Sometimes you want to automatically retry processing a message, in case it just failed due to temporary problems. In that case, you can set the `retry_queue` and `retry_delay` parameters when creating the queue.

```ruby
my_queue =
  queue('my_queue', durable: true, retry_queue: true, retry_delay: 5000)
```

This will automatically create a queue named `my_queue.retry` and use the arguments `x-dead-letter-exchange` and `x-dead-letter-routing-key` to route rejected messages to it. When routed to the retry queue, messages will wait there for the number of milliseconds specified in `retry_delay`, after which they will be redelivered to the original queue. **Note that this will not automatically catch unhandled errors. You still have to catch any errors yourself and reject your message manually for the retry mechanism to work.**

This will happen indefinitely, so if you want to bail out of this cycle at some point, it is best to use the `error_queue` option to create an error queue and then use the `MaxRetries` middleware to route messages to this error queue after a certain amount of retries.

### Implementing an error queue

You can set the `error_queue` parameter to automatically create an error queue.

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

## Documentation

If you need more in-depth information, look at [our API documentation](https://www.rubydoc.info/gems/ears).

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/ivx/ears. This project is intended to be a safe, welcoming space for collaboration, and contributors are expected to adhere to the [code of conduct](https://github.com/ivx/ears/blob/main/CODE_OF_CONDUCT.md).

## License

The gem is available as open-source under the terms of the [MIT License](https://opensource.org/licenses/MIT).

## Code of Conduct

Everyone interacting in the Ears project's codebases, issue trackers, chat rooms, and mailing lists is expected to follow the [code of conduct](https://github.com/ivx/ears/blob/main/CODE_OF_CONDUCT.md).
