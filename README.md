# PlaceOS Log Backend

Logging backend in common use across PlaceOS services.

A UDP stream will be opened to a log server if `UDP_LOG_HOST` and `UDP_LOG_PORT`
are in the environment.

Log format can be configured with `PLACE_LOG_FORMAT` equal to `line` or `json`

## Usage

```crystal
require "placeos-log-backend"

log_backend = PlaceOS::LogBackend.log_backend

Log.setup "*", :warn, log_backend

# Use `namespaces` array to configure any namespaces you wish to have
# runtime severity switching on.
PlaceOS::LogBackend.register_severity_switch_signals(
  production: App.production?,
  namespaces: namespaces,
  backend: log_backend,
)
```

## Contributors

- [Caspian Baska](https://github.com/caspiano) - creator and maintainer
