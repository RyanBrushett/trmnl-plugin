require "date"
require "json"

class Payload
  Event = Struct.new(:starts_at, :ends_at, :title, :all_day)

  WEBHOOK_LIMIT_BYTES = 2000
  EVENING_HOUR = 20
  MAX_EVENTS = 8
  MAX_TITLE_LENGTH = 60
  MINUTES_PER_DAY = 1440

  def self.truncate(text, max_length)
    return text if text.length <= max_length

    "#{text[0, max_length - 1]}…"
  end

  def self.build(events:, weather:, local_time:, max_bytes: WEBHOOK_LIMIT_BYTES)
    new(events: events, weather: weather, local_time: local_time, max_bytes: max_bytes).build
  end

  def initialize(events:, weather:, local_time:, max_bytes:)
    @events = events
    @weather = weather
    @local_time = local_time
    @max_bytes = max_bytes
  end

  def build
    all_day, timed = shown_rows
    all_day = all_day.first(MAX_EVENTS)
    timed = timed.first(MAX_EVENTS - all_day.size)
    shrink(all_day, timed) while (all_day.any? || timed.any?) && too_big?(body_with(all_day, timed))
    body_with(all_day, timed)
  end

  private

  def mode = (@local_time.hour >= EVENING_HOUR) ? "tomorrow" : "today"

  def tomorrow? = mode == "tomorrow"

  def day = tomorrow? ? @local_time.to_date + 1 : @local_time.to_date

  def day_start = midnight_of(day)

  def day_end = midnight_of(day + 1)

  def midnight_of(date) = Time.local(date.year, date.month, date.day)

  def too_big?(body)
    body.to_json.bytesize > @max_bytes
  end

  # Drops from the end of the screen: timed rows first, then all-day titles.
  def shrink(all_day, timed)
    timed.any? ? timed.pop : all_day.pop
  end

  def body_with(all_day, timed)
    {
      "merge_variables" => {
        "mode" => mode,
        "date" => day.iso8601,
        "today" => @local_time.to_date.iso8601,
        "all_day" => all_day,
        "events" => timed,
        "weather" => @weather
      }
    }
  end

  # All-day titles are a plain list, and timed events are [start_minute,
  # end_minute, title] rows read by index. A null in a row can be stripped on
  # its way to the template, which shifts every position, so no row has one.
  def shown_rows
    shown = @events.select { |event| on_day?(event) && !already_over?(event) }
    all_day, timed = shown.partition(&:all_day)
    [
      all_day.sort_by { |event| [event.starts_at, event.ends_at] }.map { |event| title_of(event) },
      timed.sort_by { |event| [event.starts_at, event.ends_at] }.map { |event| row(event) }
    ]
  end

  def on_day?(event)
    event.starts_at < day_end && event.ends_at > day_start
  end

  def already_over?(event)
    !tomorrow? && !event.all_day && event.ends_at <= @local_time
  end

  def row(event)
    [minutes_into_day(event.starts_at), minutes_into_day(event.ends_at), title_of(event)]
  end

  def title_of(event)
    self.class.truncate(event.title.strip, MAX_TITLE_LENGTH)
  end

  # Wall-clock minutes in the process time zone, not elapsed time: on the two
  # clock-change days a year the difference is an hour.
  def minutes_into_day(time)
    return 0 if time <= day_start
    return MINUTES_PER_DAY if time >= day_end

    wall_clock = time.getlocal
    wall_clock.hour * 60 + wall_clock.min
  end
end
