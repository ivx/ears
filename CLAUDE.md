# ears

Ruby gem for building RabbitMQ consumers using Bunny.

## Stack

- **Ruby** 4.0.x (see `.tool-versions`)
- **Bunny** >= 3.0.0 — AMQP client
- **connection_pool** ~> 3.0 — thread-safe channel pools for publishers
- **json** >= 2.9.0 — JSON serialization in middleware
- Dev tools: RSpec, RuboCop (rubocop-rspec, rubocop-rake), SimpleCov, YARD, Prettier (via Node)
- **Node tooling**: pnpm v11+ (pinned in `package.json#packageManager`). The JS toolchain is dev-only (Prettier on Ruby files); nothing JS ships at runtime.

## Common Commands

```bash
# Install deps
bundle install
pnpm install --frozen-lockfile

# Tests
bundle exec rspec

# Lint / format
bundle exec rubocop
pnpm run lint         # Prettier on Ruby files
pnpm run format       # Prettier --write

# Autofix rubocop
bundle exec rubocop -A

# Docs
bundle exec yard doc
```

## Directory Layout

```
lib/
  ears.rb                         # Top-level module: configure, connection, channel, setup, run!
  ears/
    configuration.rb              # Ears::Configuration — all tunable constants
    errors.rb                     # Custom error classes (required by configuration.rb)
    consumer.rb                   # Abstract base class; subclass and override #work
    consumer_wrapper.rb           # Wraps a Consumer for Bunny delivery callbacks
    setup.rb                      # Ears::Setup — DSL for exchange/queue/consumer wiring
    publisher.rb                  # Ears::Publisher — publish and publish_with_confirmation
    publisher_channel_pool.rb     # Thread-safe ConnectionPool for publisher channels
    publisher_confirmation_handler.rb
    publisher_retry_handler.rb
    middleware.rb                  # Middleware base
    middlewares/
      appsignal.rb
      json.rb                      # Deserializes JSON payload before #work
      max_retries.rb
    testing.rb                    # Ears::Testing module entry-point
    testing/
      matchers.rb
      message_capture.rb
      publisher_mock.rb
      test_helper.rb
spec/                             # RSpec specs (mirrors lib/ structure)
```

## Architecture

**Consumer pattern:** Subclass `Ears::Consumer`, call `.configure(queue:, exchange:, routing_keys:, ...)` in the class body, override `#work(delivery_info, metadata, payload)` returning `:ack`, `:reject`, or `:requeue`. Middleware chain is applied in reverse order around `#work`.

**Publisher pattern:** Instantiate `Ears::Publisher.new(exchange_name)`, call `#publish(data, routing_key:)` or `#publish_with_confirmation(data, routing_key:)`. Internally uses `PublisherChannelPool` (two `ConnectionPool` instances — one standard, one with confirms). Pool is lazy-initialised with a mutex for thread safety and is fork-safe (resets on PID change).

**Setup DSL:** `Ears.setup { exchange(...); queue(...); consumer(...) }` or `Ears.setup_consumers(*classes)` which auto-wires from each class's `.configure` metadata.

**Configuration knobs** (set via `Ears.configure { |c| c.foo = ... }`): `rabbitmq_url`, `connection_name` (required), `publisher_pool_size` (32), `publisher_pool_timeout` (2s), `publisher_confirms_pool_size` (32), `publisher_confirms_timeout` (5s), plus retry/backoff params.

## Testing Support

`require 'ears/testing'` — provides `Ears::Testing::TestHelper` (RSpec include), `PublisherMock`, `MessageCapture`, and custom matchers (`have_been_published`).

## Known Tech Debt

- `Metrics/MethodLength` is suppressed for `Configuration#initialize` (initialises ~15 instance variables from constants; an options-hash refactor would be the real fix).
- `.rubocop_todo.yml` may have lingering entries — check before adding new inline disables.
