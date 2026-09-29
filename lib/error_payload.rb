require "payload"

class ErrorPayload
  MODE = "error"
  MAX_MESSAGE_LENGTH = 200

  def self.build(exception, local_time:)
    {
      "merge_variables" => {
        "mode" => MODE,
        "error" => "#{exception.class}: #{Payload.truncate(exception.message, MAX_MESSAGE_LENGTH)}",
        "where" => origin(exception),
        "at" => local_time.strftime("%Y-%m-%d %H:%M")
      }
    }
  end

  def self.origin(exception)
    location = exception.backtrace_locations&.first
    return "unknown" unless location

    "#{File.basename(location.path)}:#{location.lineno}"
  end
  private_class_method :origin
end
