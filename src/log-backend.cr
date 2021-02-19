require "action-controller"

module PlaceOS::LogBackend
  LOG_STDOUT    = ActionController.default_backend
  LOGSTASH_HOST = ENV["LOGSTASH_HOST"]?
  LOGSTASH_PORT = ENV["LOGSTASH_PORT"]?

  def self.log_backend(
    logstash_host : String? = ENV["LOGSTASH_HOST"]?.presence,
    logstash_port : Int32? = ENV["LOGSTASH_PORT"]?.try(&.to_i?),
    default_backend : Log::IOBackend = ActionController.default_backend
  )
    if logstash_host
      abort("LOGSTASH_PORT is either malformed or not present in environment") if logstash_port.nil?

      # Logstash UDP Input
      logstash = UDPSocket.new
      logstash.connect logstash_host, logstash_port
      logstash.sync = false

      # debug at the broadcast backend level, however this will be filtered
      # by the bindings
      ::Log::BroadcastBackend.new.tap do |backend|
        backend.append(default_backend, :trace)
        backend.append(ActionController.default_backend(
          io: logstash,
          formatter: ActionController.json_formatter
        ), :trace)
      end
    else
      default_backend
    end
  end
end
