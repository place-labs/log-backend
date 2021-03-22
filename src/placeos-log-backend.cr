require "action-controller"
require "log"

module PlaceOS::LogBackend
  STDOUT        = ActionController.default_backend
  LOGSTASH_HOST = ENV["LOGSTASH_HOST"]?.presence
  LOGSTASH_PORT = ENV["LOGSTASH_PORT"]?.try &.to_i?

  def self.log_backend(
    logstash_host : String? = LOGSTASH_HOST,
    logstash_port : Int32? = LOGSTASH_PORT,
    default_backend : ::Log::IOBackend = ActionController.default_backend
  )
    return default_backend if logstash_host.nil?

    abort("LOGSTASH_PORT is either malformed or not present in environment") if logstash_port.nil?

    # Logstash UDP Input
    logstash = begin
      UDPSocket.new.tap do |socket|
        socket.connect logstash_host, logstash_port
        socket.sync = false
      end
    rescue IO::Error
      Log.error { {message: "failed to connect to logstash", host: host, port: port} }
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
