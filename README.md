# PlaceOS Log Backend

Logging backend in common use across PlaceOS services.

A UDP stream will be opened to a log server if `UDP_LOG_HOST` and `UDP_LOG_PORT`
are in the environment.

## Usage

```crystal
require "placeos-log-backend"
Log.setup "*", :warn, PlaceOS::LogBackend.log_backend
```

## Contributors

- [Caspian Baska](https://github.com/caspiano) - creator and maintainer
