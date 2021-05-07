# Changelog

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
