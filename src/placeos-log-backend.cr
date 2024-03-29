require "action-controller"
require "log"
require "opentelemetry-instrumentation/log_backend"

require "./ext/log/broadcast_backend"
require "./placeos-log-backend/format"
require "./placeos-log-backend/constants"
require "./placeos-log-backend/new_relic_log_exporter"

module PlaceOS::LogBackend
  Log = ::Log.for(self)

  STDOUT = ActionController.default_backend

  # Hook to toggle `Log` instances' `:trace` severity
  # ## `enabled`
  # - `true`
  # `:trace` for _all_ `Log` instances.
  #
  # - `false`
  # returns `namespaces`'s `Log`s to `:info` if `production`
  # is `true` and otherwise it is set to `:debug`.
  # `Log`'s that are not registered under `namespaces` are toggled to `default`.
  #
  def self.trace_logging(
    enabled : Bool,
    production : Bool,
    namespaces : Array(String),
    default : ::Log::Severity,
    backend
  )
    production_log_level = production ? default : ::Log::Severity::Debug
    namespace_log_level = enabled ? ::Log::Severity::Trace : production_log_level
    default_log_level = enabled ? ::Log::Severity::Trace : default

    ::Log.builder.bind "*", default_log_level, backend
    Log.info { "default log level changed to #{default_log_level}" }

    namespaces.each do |namespace|
      ::Log.builder.bind(namespace, namespace_log_level, backend)
    end
    Log.info { "#{namespaces.join(", ")} log level changed to #{namespace_log_level}" }
  end

  class_getter trace : Bool = false

  # Registers callbacks for USR1 and USR2
  #
  # **`USR1`**
  # toggles `:trace` for _all_ `Log` instances
  # `namespaces`'s `Log`s to `:info` if `production` is `true`,
  # otherwise it is set to `:debug`.
  # `Log`'s not registered under `namespaces` are toggled to `default`
  #
  # ## Usage
  # - `$ kill -USR1 ${the_application_pid}`
  def self.register_severity_switch_signals(
    production : Bool,
    namespaces : Array(String),
    default : ::Log::Severity = ::Log::Severity::Info,
    backend = self.log_backend
  ) : Nil
    # Allow signals to change the log level at run-time
    Signal::USR1.trap do |signal|
      @@trace = !@@trace
      trace_logging(@@trace, production, namespaces, default, backend)

      # Ignore standard behaviour of the signal
      signal.ignore

      # we need to re-register our interest in the signal
      register_severity_switch_signals(production, namespaces, default, backend)
    end
  end

  def self.log_backend(
    udp_log_host : String? = UDP_LOG_HOST,
    udp_log_port : Int32? = UDP_LOG_PORT,
    default_backend : ::Log::IOBackend = ActionController.default_backend,
    format : Format = LOG_FORMAT,
    service_name : String? = nil,
    service_version : String? = nil
  )
    case format
    in .line? then default_backend.formatter = ActionController.default_formatter
    in .json? then default_backend.formatter = ActionController.json_formatter
    end

    backends = [] of {::Log::Severity, ::Log::Backend}
    backends << {::Log::Severity::Trace, default_backend}

    unless udp_log_host.nil?
      abort("UDP_LOG_PORT is either malformed or not present in environment") if udp_log_port.nil?

      # Logstash UDP Input
      udp_stream = begin
        UDPSocket.new.tap do |socket|
          socket.connect udp_log_host, udp_log_port
          socket.sync = false
        end
      rescue IO::Error
        Log.error { {message: "failed to connect to UDP log consumer", host: udp_log_host, port: udp_log_port} }
        nil
      end

      if udp_stream
        backends << {::Log::Severity::Trace, ActionController.default_backend(
          io: udp_stream,
          formatter: ActionController.json_formatter
        )}
      end
    end

    unless OTEL_EXPORTER_OTLP_ENDPOINT.nil?
      # OpenTelemetry's LogBackend has to log on the same fiber, hence the use of sync dispatch mode.
      backends << {::Log::Severity::Trace, OpenTelemetry::Instrumentation::LogBackend.new}
    end

    if service_name && service_version && (new_relic_key = NEW_RELIC_LICENSE_KEY) && (new_relic_http_log_endpoint = NEW_RELIC_HTTP_LOG_ENDPOINT)
      backends << {
        ::Log::Severity::Info,
        NewRelicLogBackend.new(service_name, service_version, new_relic_http_log_endpoint, new_relic_key),
      }
    end

    if backends.size == 1
      backends.first.last
    else
      # Debug at the broadcast backend level, however this will be filtered by the bindings.
      ::Log::BroadcastBackend.new.tap do |broadcast_backend|
        backends.each do |severity, backend|
          broadcast_backend.append(backend, severity)
        end
      end
    end
  end
end
