require "test_helper"
require "updater"
require "weather"

class UpdaterTest < Minitest::Test
  class FakeWeather
    attr_reader :requests

    def initialize(rows: [[14, 13, 3, 6]], error: nil)
      @rows = rows
      @error = error
      @requests = []
    end

    def next_hours(local_time:, hours:)
      @requests << {local_time: local_time, hours: hours}
      raise @error if @error

      @rows
    end
  end

  AFTERNOON = Time.new(2026, 9, 29, 14, 30, 0, SVALBARD_OFFSET)
  EVENING = Time.new(2026, 9, 29, 21, 0, 0, SVALBARD_OFFSET)

  def updater(weather: FakeWeather.new, events: [], local_time: AFTERNOON)
    Updater.new(weather: weather, events_source: -> { events }, local_time: local_time)
  end

  def test_builds_a_payload_from_weather_and_events
    event = Payload::Event.new(title: "Dentist", starts_at: Time.new(2026, 9, 29, 15, 0, 0, SVALBARD_OFFSET),
      ends_at: Time.new(2026, 9, 29, 16, 0, 0, SVALBARD_OFFSET))

    variables = updater(events: [event]).body.fetch("merge_variables")

    assert_equal ["today", [[900, 960, "Dentist"]], [[14, 13, 3, 6]]],
      variables.values_at("mode", "events", "weather")
  end

  def test_asks_for_eight_hours_starting_now_during_the_day
    weather = FakeWeather.new
    updater(weather: weather).body

    assert_equal [{local_time: AFTERNOON, hours: 8}], weather.requests
  end

  def test_asks_for_the_same_window_in_the_evening_when_the_schedule_flips_to_tomorrow
    weather = FakeWeather.new
    body = updater(weather: weather, local_time: EVENING).body

    assert_equal [[{local_time: EVENING, hours: 8}], "tomorrow"],
      [weather.requests, body.dig("merge_variables", "mode")]
  end

  def test_shows_the_error_page_when_the_weather_fails
    weather = FakeWeather.new(error: Weather::Error.new("Open-Meteo returned HTTP 503"))

    variables = updater(weather: weather).body.fetch("merge_variables")

    assert_equal ["error", "Weather::Error: Open-Meteo returned HTTP 503"], variables.values_at("mode", "error")
  end

  def test_shows_the_error_page_when_the_events_source_fails
    broken = Updater.new(weather: FakeWeather.new, events_source: -> { raise "calendar exploded" }, local_time: AFTERNOON)

    assert_equal "error", broken.body.dig("merge_variables", "mode")
  end

  def test_does_not_swallow_errors_that_are_not_standard_errors
    interrupted = Updater.new(weather: FakeWeather.new, events_source: -> { raise Interrupt }, local_time: AFTERNOON)

    assert_raises(Interrupt) { interrupted.body }
  end
end
