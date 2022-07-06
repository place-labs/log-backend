require "action-controller/logger"
require "nbchannel"
require "tasker"

require "./constants"

class NewRelicLogBackend < Log::Backend
  protected getter service_name : String
  protected getter service_version : String

  protected getter endpoint : String
  protected getter key : String

  def initialize(
    @service_name,
    @service_version,
    @endpoint,
    @key,
    @dispatch_mode : Log::DispatchMode = :async
  )
    # Empty peridically or when buffer is full
    @task = Tasker.every(PlaceOS::NEW_RELIC_LOG_PERIOD) { flush }

    # Start buffering logs asynchronously
    spawn { buffer_logs }

    super(@dispatch_mode)
  end

  def write(entry : Log::Entry)
    log_channel.send(entry)
  end

  @task : Tasker::Task?
  @buffer : Array(Log::Entry) = Array(Log::Entry).new(PlaceOS::NEW_RELIC_BUFFER_CAPACITY)

  protected getter buffer_lock = Mutex.new(protection: :reentrant)
  protected getter log_channel : NBChannel(Log::Entry) = NBChannel(Log::Entry).new

  protected def with_buffer
    buffer_lock.synchronize { yield @buffer }
  end

  protected def buffer_logs
    loop do
      log = log_channel.receive
      with_buffer do |buffer|
        buffer << log
        flush if buffer.size == PlaceOS::NEW_RELIC_BUFFER_CAPACITY
      end
    end
  rescue
  end

  protected def flush
    with_buffer do |buffer|
      return if buffer.empty?

      body = JSON.build do |json|
        json.object do
          json.field "common" do
            {
              "attributes": {
                "service_name":    service_name,
                "service_version": service_version,
              },
            }.to_json(json)
          end
          json.field "logs" do
            json.array do
              buffer.each do |entry|
                # typeof doesn't execute anything
                attributes = {} of String => typeof(ActionController.log_metadata_to_raw(entry.data[:check]))
                attributes["level"] = entry.severity.label
                attributes["source"] = entry.source

                # Add context tags
                {entry.context, entry.data}.each &.each { |k, v| attributes[k.to_s] = ActionController.log_metadata_to_raw(v) }

                if exception = entry.exception
                  attributes["exception"] = exception.inspect_with_backtrace
                end

                {
                  timestamp:  entry.timestamp,
                  message:    entry.message,
                  attributes: attributes,
                }.to_json(json)
              end
            end
          end
        end
      end

      HTTP::Client.post(endpoint, body: body, headers: HTTP::Headers{"Api-Key" => key, "Content-Type" => "application/json"})

      # Empty buffer after writing it
      buffer.clear
    end
  end

  def finalize
    log_channel.close
    @task.try &.cancel
  end
end
