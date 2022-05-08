module PlaceOS
  # OTLP configuration
  OTEL_EXPORTER_OTLP_ENDPOINT = ENV["OTEL_EXPORTER_OTLP_ENDPOINT"]?.presence
  OTEL_EXPORTER_OTLP_HEADERS  = ENV["OTEL_EXPORTER_OTLP_HEADERS"]?.presence

  # Api Keys
  OTEL_EXPORTER_OTLP_API_KEY = ENV["OTEL_EXPORTER_OTLP_API_KEY"]?.presence
  NEW_RELIC_LICENSE_KEY      = ENV["NEW_RELIC_LICENSE_KEY"]?.presence
  ELASTIC_APM_API_KEY        = ENV["ELASTIC_APM_API_KEY"]?.presence

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
end
