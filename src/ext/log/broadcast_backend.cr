require "log"

class Log::BroadcastBackend < Log::Backend
  def append(backend : Log::Backend, level : Severity)
    # Ignore addition of self to set of broadcast backends
    previous_def unless backend == self
  end
end
