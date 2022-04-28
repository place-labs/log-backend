require "http"
require "opentelemetry-instrumentation"

class HTTP::Client
  def_around_exec do |request|
    # Set the `traceparent` header of current request
    request.headers["traceparent"] = OpenTelemetry.trace.trace_id
    yield
  end
end
