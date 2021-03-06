# Changelog

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
