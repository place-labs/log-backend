require "action-controller"
require "log"

require "./ext/log/broadcast_backend"

module PlaceOS::LogBackend
  Log           = ::Log.for(self)
  STDOUT        = ActionController.default_backend
  UDP_LOG_HOST = ENV["UDP_LOG_HOST"]?.presence || ENV["LOGSTASH_HOST"]?.presence
  UDP_LOG_PORT = (ENV["UDP_LOG_PORT"]?.presence || ENV["LOGSTASH_PORT"]?.presence).try &.to_i?

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

  # Registers callbacks for USR1 and USR2
  #
  # **`USR1`**
  # turns on `:trace` for _all_ `Log` instances
  #
  # **`USR2`**
  # returns `namespaces`'s `Log`s to `:info` if `production` is `true`,
  # otherwise it is set to `:debug`.
  # `Log`'s not registered under `namespaces` are toggled to `default`
  #
  # ## Usage
  # - `$ kill -USR2 ${the_application_pid}`
  # - `$ kill -USR2 ${the_application_pid}`
  def self.register_severity_switch_signals(
    production : Bool,
    namespaces : Array(String),
    default : ::Log::Severity = ::Log::Severity::Info,
    backend = self.log_backend
  ) : Nil
    # Allow signals to change the log level at run-time
    logging = Proc(Signal, Nil).new do |signal|
      trace_logging(signal.usr1?, production, namespaces, default, backend)
      # Ignore standard behaviour of the signal
      signal.ignore
    end

    Signal::USR1.trap &logging
    Signal::USR2.trap &logging
  end

  @[Deprecated(
    <<-MESSAGE
      `logstash_host` and `logstash_port` arguments are deprecated.
      Use `udp_source_host` and `udp_source_port` instead.
    MESSAGE
  )]
  def self.log_backend(
    logstash_host : String? = UDP_LOG_HOST,
    logstash_port : Int32? = UDP_LOG_PORT,
    default_backend : ::Log::IOBackend = ActionController.default_backend
  )
    log_backend(udp_source_host: logstash_host, udp_source_port: logstash_port)
  end

  def self.log_backend(
    udp_source_host : String? = UDP_LOG_HOST,
    udp_source_port : Int32? = UDP_LOG_PORT,
    default_backend : ::Log::IOBackend = ActionController.default_backend
  )
    return default_backend if logstash_host.nil?

    abort("UDP_LOG_PORT is either malformed or not present in environment") if logstash_port.nil?

    # Logstash UDP Input
    logstash = begin
      UDPSocket.new.tap do |socket|
        socket.connect logstash_host, logstash_port
        socket.sync = false
      end
    rescue IO::Error
      Log.error { {message: "failed to connect to logstash", host: logstash_host, port: logstash_port} }
      nil
    end

    # Use the default backend if connection to logstash failed
    return default_backend if logstash.nil?

    # Debug at the broadcast backend level, however this will be filtered by
    # the bindings.
    ::Log::BroadcastBackend.new.tap do |backend|
      backend.append(default_backend, :trace)
      backend.append(ActionController.default_backend(
        io: logstash,
        formatter: ActionController.json_formatter
      ), :trace)
    end
  end
end
