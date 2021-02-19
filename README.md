# PlaceOS Log Backend

Logging backend in common use across PlaceOS services.
Will open a UDP stream to a logstash server if `LOGSTASH_HOST` and `LOGSTASH_PORT` are configured.

## Usage

```crystal
require "placeos-log-backend"
Log.setup "*", :warn, PlaceOS::LogBackend.log_backend
```

## Contributors

- [Caspian Baska](https://github.com/caspiano) - creator and maintainer
