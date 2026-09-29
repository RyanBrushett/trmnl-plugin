require "date"
require "json"

class Payload
  Event = Struct.new(:starts_at, :ends_at, :title, :work, :all_day)

  WEBHOOK_LIMIT_BYTES = 2000
  EVENING_HOUR = 20
  MAX_EVENTS = 8
  MAX_TITLE_LENGTH = 60
  WORK_EVENT_TITLE = "Meeting"
  UNTITLED_EVENT_TITLE = "(No title)"
  MINUTES_PER_DAY = 1440

  def self.mode(local_time)
    (local_time.hour >= EVENING_HOUR) ? "tomorrow" : "today"
  end

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
    rows = event_rows.first(MAX_EVENTS)
    rows.pop while rows.any? && too_big?(body_with(rows))
    body_with(rows)
  end

  private

  def tomorrow? = self.class.mode(@local_time) == "tomorrow"

  def day = tomorrow? ? @local_time.to_date + 1 : @local_time.to_date

  def day_start = midnight_of(day)

  def day_end = midnight_of(day + 1)

  def midnight_of(date) = Time.local(date.year, date.month, date.day)

  def too_big?(body)
    body.to_json.bytesize > @max_bytes
  end

  def body_with(event_rows)
    {
      "merge_variables" => {
        "mode" => self.class.mode(@local_time),
        "date" => day.iso8601,
        "today" => @local_time.to_date.iso8601,
        "events" => event_rows,
        "weather" => @weather
      }
    }
  end

  def event_rows
    shown = @events.select { |event| on_day?(event) && !already_over?(event) }
    shown.sort_by { |event| [event.all_day ? 0 : 1, event.starts_at, event.ends_at] }
      .map { |event| row(event) }
  end

  def on_day?(event)
    event.starts_at < day_end && event.ends_at > day_start
  end

  def already_over?(event)
    !tomorrow? && !event.all_day && event.ends_at <= @local_time
  end

  # Rows are positional, [start_minute, end_minute, title], because the TRMNL
  # template reads them by index. All-day events have no minutes.
  def row(event)
    return [nil, nil, title_of(event)] if event.all_day

    [minutes_into_day(event.starts_at), minutes_into_day(event.ends_at), title_of(event)]
  end

  def title_of(event)
    return WORK_EVENT_TITLE if event.work

    title = event.title.to_s.strip
    self.class.truncate(title.empty? ? UNTITLED_EVENT_TITLE : title, MAX_TITLE_LENGTH)
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
