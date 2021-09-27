require "action-controller"
require "log"

require "./ext/log/broadcast_backend"

module PlaceOS::LogBackend
  enum Format
    Line
    JSON
  end

  Log = ::Log.for(self)

  STDOUT = ActionController.default_backend

  LOG_FORMAT = ENV["PLACE_LOG_FORMAT"]?.presence.try { |format| Format.parse format } || Format::Line

  UDP_LOG_HOST = self.env_with_deprecation("UDP_LOG_HOST", "LOGSTASH_HOST")
  UDP_LOG_PORT = self.env_with_deprecation("UDP_LOG_PORT", "LOGSTASH_PORT").try &.to_i?

  # The first argument will be treated as the correct environment variable.
  # Presence of follwoing vars will produce warnings.
  protected def self.env_with_deprecation(*args) : String?
    if correct_env = ENV[args.first]?.presence
      return correct_env
    end

    args[1..].each do |env|
      found = ENV[env]?.presence
      if found
        Log.warn { "using deprecated env var #{env}, please use #{args.first}" }
        return found
      end
    end
  end

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

  def self.log_backend(
    udp_log_host : String? = UDP_LOG_HOST,
    udp_log_port : Int32? = UDP_LOG_PORT,
    default_backend : ::Log::IOBackend = ActionController.default_backend,
    format : Format = LOG_FORMAT
  )
    case format
    in .line? then default_backend.formatter = ActionController.default_formatter
    in .json? then default_backend.formatter = ActionController.json_formatter
    end

    return default_backend if udp_log_host.nil?

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

    # Use the default backend if connection to UDP log consumer failed
    return default_backend if udp_stream.nil?

    # Debug at the broadcast backend level, however this will be filtered by
    # the bindings.
    ::Log::BroadcastBackend.new.tap do |backend|
      backend.append(default_backend, :trace)
      backend.append(ActionController.default_backend(
        io: udp_stream,
        formatter: ActionController.json_formatter
      ), :trace)
    end
  end
end
