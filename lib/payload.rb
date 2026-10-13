require "date"
require "json"

class Payload
  Event = Struct.new(:starts_at, :ends_at, :title, :all_day)

  #: (Integer, Integer, String, Bool) -> Payload::TimedEntry
  TimedEntry = Data.define(:start_minutes_into_day, :end_minutes_into_day, :title, :finished) do
    def finished? = !!finished
    def to_a = [start_minutes_into_day, end_minutes_into_day, title, finished ? 1 : 0]
  end
  private_constant :TimedEntry

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
    all_day, timed = shown_all_day_and_timed
    all_day = all_day.first(MAX_EVENTS)
    room_for_timed = MAX_EVENTS - all_day.size
    drop_least_useful_entry(timed) while timed.size > room_for_timed
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

  def shrink(all_day, timed)
    timed.any? ? drop_least_useful_entry(timed) : all_day.pop
  end

  def drop_least_useful_entry(timed)
    oldest_finished = timed.index(&:finished?)
    oldest_finished ? timed.delete_at(oldest_finished) : timed.pop
  end

  def body_with(all_day, timed)
    {
      "merge_variables" => {
        "mode" => mode,
        "date" => day.iso8601,
        "today" => @local_time.to_date.iso8601,
        "all_day" => all_day,
        "events" => timed.map(&:to_a),
        "weather" => @weather.map(&:to_a)
      }
    }
  end

  def shown_all_day_and_timed
    shown = @events.select { |event| on_day?(event) }
    all_day, timed = shown.partition(&:all_day)
    [
      all_day.sort_by { |event| [event.starts_at, event.ends_at] }.map { |event| title_of(event) },
      timed.sort_by { |event| [event.starts_at, event.ends_at] }.map { |event| timed_entry(event) }
    ]
  end

  def on_day?(event)
    event.starts_at < day_end && event.ends_at > day_start
  end

  def timed_entry(event)
    TimedEntry.new(
      start_minutes_into_day: minutes_into_day(event.starts_at),
      end_minutes_into_day: minutes_into_day(event.ends_at),
      title: title_of(event),
      finished: event.ends_at <= @local_time
    )
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
