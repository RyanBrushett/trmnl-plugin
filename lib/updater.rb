require "error_payload"
require "payload"

class Updater
  HOURS_SHOWN = 8

  def initialize(weather:, events_source:, local_time:)
    @weather = weather
    @events_source = events_source
    @local_time = local_time
  end

  def body
    Payload.build(events: @events_source.call, weather: forecast, local_time: @local_time)
  rescue => error
    ErrorPayload.build(error, local_time: @local_time)
  end

  private

  def forecast
    @weather.next_hours(local_time: @local_time, hours: HOURS_SHOWN)
  end
end
