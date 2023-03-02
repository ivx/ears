# Changelog

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
