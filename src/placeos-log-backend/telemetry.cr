require "opentelemetry-instrumentation"
require "opentelemetry-instrumentation/src/opentelemetry/instrumentation/**"

module PlaceOS::LogBackend
  # OTLP configuration
  OTEL_EXPORTER_OTLP_ENDPOINT = ENV["OTEL_EXPORTER_OTLP_ENDPOINT"]?.presence
  OTEL_EXPORTER_OTLP_HEADERS  = ENV["OTEL_EXPORTER_OTLP_HEADERS"]?.presence

  # Api Keys
  OTEL_EXPORTER_OTLP_API_KEY = ENV["OTEL_EXPORTER_OTLP_API_KEY"]?.presence
  NEW_RELIC_LICENSE_KEY      = ENV["NEW_RELIC_LICENSE_KEY"]?.presence
  ELASTIC_APM_API_KEY        = ENV["ELASTIC_APM_API_KEY"]?.presence

  # :nodoc:
  module Telemetry
    Log = ::Log.for(self)
  end

  # Call this method to configure OpenTelemetry.
  #
  # The client will not initialize if the `OTEL_EXPORTER_OTLP_ENDPOINT` environment
  # variable is not present.
  #
  # ## Usage
  #
  # ```
  # PlaceOS::LogBackend.configure_opentelemetry(
  #   service_name: APP_NAME,
  #   service_version: VERSION,
  # )
  # ```
  #
  # ## Environment
  #
  # *OTLP configuration*
  # - `OTEL_EXPORTER_OTLP_ENDPOINT`
  # - `OTEL_EXPORTER_OTLP_HEADERS`: e.g `Hello=world,Foo=bar`
  #
  # *Api Keys*
  # - `OTEL_EXPORTER_OTLP_API_KEY`
  # - `NEW_RELIC_LICENSE_KEY`
  # - `ELASTIC_APM_API_KEY`
  def self.configure_opentelemetry(
    service_name : String,
    service_version : String,
    endpoint : String? = OTEL_EXPORTER_OTLP_ENDPOINT,
    header_environment : String? = OTEL_EXPORTER_OTLP_HEADERS,
    otel_key : String? = OTEL_EXPORTER_OTLP_API_KEY,
    new_relic_key : String? = NEW_RELIC_LICENSE_KEY,
    elastic_apm_key : String? = ELASTIC_APM_API_KEY
  ) : Nil
    if endpoint.nil?
      Telemetry::Log.info { "OTEL_EXPORTER_OTLP_ENDPOINT not configured" }
      return
    end

    headers = HTTP::Headers.new

    # Set HTTP Headers from the environment
    if header_environment
      header_environment.split(',').map(&.split('=', limit: 2)).each do |(key, value)|
        headers[key] = value
      end
    end

    # Authorization
    if otel_key
      headers["Api-Key"] = otel_key
    elsif elastic_apm_key
      headers["Authorization"] = "ApiKey #{elastic_apm_key}"
    elsif new_relic_key
      headers["Api-Key"] = new_relic_key
    end

    OpenTelemetry.configure do |config|
      config.service_name = service_name
      config.service_version = service_version
      config.exporter = OpenTelemetry::Exporter.new(variant: :http) do |exporter|
        exporter.as(OpenTelemetry::Exporter::Http).headers = headers
        exporter.as(OpenTelemetry::Exporter::Http).endpoint = endpoint
      end
    end

    Telemetry::Log.info { "using #{OpenTelemetry::Instrumentation::Registry.instruments.join(", ")}" }
  end
end
