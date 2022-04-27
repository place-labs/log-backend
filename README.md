# PlaceOS Log Backend

Logging backend in common use across PlaceOS services.

A UDP stream will be opened to a log server if `UDP_LOG_HOST` and `UDP_LOG_PORT`
are in the environment.

## Usage

```crystal
require "placeos-log-backend"
require "placeos-log-backend/telemetry"

log_backend = PlaceOS::LogBackend.log_backend

Log.setup "*", :warn, log_backend

# Use `namespaces` array to configure any namespaces you wish to have
# runtime severity switching on.
PlaceOS::LogBackend.register_severity_switch_signals(
  production: App.production?,
  namespaces: namespaces,
  backend: log_backend,
)

# To configure OpenTelemetry
#
# *OTLP configuration*
# - `OTEL_EXPORTER_OTLP_ENDPOINT`
# - `OTEL_EXPORTER_OTLP_HEADERS`: e.g `Hello=world,Foo=bar`
#
# *Api Keys*
# - `OTEL_EXPORTER_OTLP_API_KEY`
# - `NEW_RELIC_LICENSE_KEY`
# - `ELASTIC_APM_API_KEY`
PlaceOS::LogBackend.configure_opentelemetry(
  service_name: APP_NAME,
  service_version: VERSION,
  endpoint: OTEL_EXPORTER_OTLP_ENDPOINT,
)
```

## Contributors

- [Caspian Baska](https://github.com/caspiano) - creator and maintainer
