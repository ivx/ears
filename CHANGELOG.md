# Changelog

## 0.22.2 (2025-01-19)

### Fixed

- Publisher now proactively detects and recovers from closed channels before attempting to publish, preventing `Bunny::ChannelAlreadyClosed` errors when channels are closed by RabbitMQ (e.g., due to missing queues or other channel-level errors)

## 0.22.1 (2025-09-11)

- Add optional `routing_key_match` parameter to `#published_messages` in `Ears::Testing::TestHelper`
- Add `#last_published_payload` to `Ears::Testing::TestHelper`

## 0.22.0 (2025-09-11)

- Support publisher confirms in `Ears::Publisher`

## 0.21.1 (2025-09-09)

- Add testing abstractions: `Ears::Testing::TestHelper`, `Ears::Testing::MessageCapture`, and `Ears::Testing::PublisherMock`

## 0.21.0 (2025-09-08)

- Introduce Ears::Publisher with thread-safe channel pooling
- Introduce configurable logger

## 0.20.0 (2025-06-02)

- Drop support for Ruby 3.1

## 0.19.0 (2025-03-10)

- Enhance Consumer#configure method and Ears.setup_consumers to accept `prefetch` option, which will be passed to Ears::Setup.

## 0.18.0 (2025-01-20)

- Enhance Consumer#configure method to accept custom queue arguments.

## 0.17.0 (2025-01-20)

- Drop support for ruby 3.0

## 0.16.0 (2025-01-08)

- Enhance Consumer#configure method to accept threads option, which will be passed to Ears::Setup.

## 0.15.0 (2025-01-14)

- Drop support for ruby 2.7
- Add support for ruby 3.4

## 0.14.1 (2024-07-31)

- Add instrumentation around block in Appsignal middleware

## 0.14.0 (2024-07-29)

- **[Breaking]** Adjust Appsignal middleware to use `Appsignal.monitor`.
  To use the middleware the `appsignal` gem in version `>= 3.11.0` is required.
  The configuration of the middleware changed and now only requires one option `class_name` and an optional `namespace`.

## 0.13.0 (2023-11-07)

- Allow adding multiple routing keys to the consumer configuration, configure method within consumer will only accept `routing_keys` array instead of `routing_key` string

## 0.12.0 (2023-10-26)

- add new interface to setup consumers including their exchange, queue and binding the queue to the exchange via routing key via `Ears.setup_consumers` and `configure(queue:, exchange:,routing_key:, ...)` for Ears::Consumers subclasses

## 0.11.2 (2023-10-25)

- Add documentation generation via yard

## 0.11.1 (2023-09-08)

- Bugfix: trapped signals INT and TERM now calls correctly previous set signal handler

## 0.11.0 (2023-05-30)

- **[Breaking]**: Provide the Bunny connection option `recovery_attempts` in Ears configuration. It
  comes with a default of 10 attempts. When the number of recovery attempts are exhausted, Ears will
  raise a `MaxRecoveryAttemptsExhaustedError`.

## 0.10.1 (2023-05-22)

- Reset channel on Ears.stop!

## 0.10.0 (2023-05-16)

- Add Ears.stop! method to be able to close the connection and remove consumers.

## 0.9.3 (2023-03-02)

- Update gem ownership information

## 0.9.2 (2023-03-02)

- Remove Rubygems MFA requirement to prepare automatic releases

## 0.9.1 (2023-02-28)

- Fix bug where queue arguments were ignored with error_queue option

## 0.9.0 (2023-01-09)

- Add option to configure recover_from_connection_close

## 0.8.2 (2022-11-25)

- default JSON middleware error handler to reject

## 0.8.1 (2022-04-08)

- do not rescue errors outside the scope of the error handler in JSON middleware

## 0.8.0 (2022-04-08)

- JSON middleware now requires an `on_error` callback in the options

## 0.7.2 (2022-02-24)

- change retry middleware to gracefully handle messages that do not have a header in their metadata

## 0.7.1 (2021-12-21)

- explicitly report Appsignal errors in middleware to make it more reliable

## 0.7.0 (2021-12-06)

- add options to create retry and error queues

## 0.6.0 (2021-11-18)

- add `connection_name` to configuration and make it a mandatory setting
- validate configuration after calling `configure`

## 0.5.0 (2021-11-03)

- fix the fact that the configuration was never used and bunny silently fell back to the `RABBITMQ_URL` env var

## 0.4.3 (2021-07-26)

### Changes

- Ears will not exit gracefully on unhandled errors anymore. You have to take care of proper flushing and cleanup yourself (see README for example).

## 0.3.3 (2021-06-07)

### Changes

- Ears will now exit gracefully on unhandled errors to give the application a chance to do flushing and cleanup work

## 0.3.2 (2021-05-21)

### Changes

- added YARD documentation and usage instructions to README
- introduced `Ears::Middleware` as an abstract base class for middlewares

## 0.3.1 (2021-05-07)

### Changes

- internally, user-defined `Ears::Consumer` instances are now wrapped by `Ears::ConsumerWrapper` to make the user-defined class smaller and easier to test

## 0.3.0 (2021-05-07)

### Breaking

- `Ears::Middlewares::JSON` now symbolizes the keys by default

### Changes

- you can now configure `Ears::Middlewares::JSON` with `use Ears::Middlewares::JSON, symbolize_keys: false`

## 0.2.1 (2021-05-07)

### Changes

- you can now call `Ears.configure` to set a custom RabbitMQ URL to connect to

## 0.2.0 (2021-05-07)

### Breaking

- a middleware class is not instantiated with options when passed to `use`

### Changes

- middlewares can now accept options
- added an Appsignal middleware to monitor consumers

## 0.1.0 (2021-04-23)

Initial release.
