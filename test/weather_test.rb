require "test_helper"
require "weather"

class WeatherTest < Minitest::Test
  URL = "https://api.open-meteo.com/v1/forecast"
  LONGYEARBYEN = {lat: 78.216667, lon: 15.633333}.freeze

  def setup
    stub_request(:get, URL).with(query: hash_including({})).to_return(
      status: 200,
      body: fixture("open_meteo.json"),
      headers: {"Content-Type" => "application/json"}
    )
    @weather = Weather.new(**LONGYEARBYEN)
    @afternoon = Time.new(2026, 9, 29, 14, 30, 0, SVALBARD_OFFSET)
  end

  def test_returns_the_requested_number_of_hours
    assert_equal 8, @weather.next_hours(local_time: @afternoon, hours: 8).size
    assert_equal 6, @weather.next_hours(local_time: @afternoon, hours: 6).size
  end

  def test_starts_at_the_current_local_hour
    hours = @weather.next_hours(local_time: @afternoon, hours: 8).map(&:first)

    assert_equal [14, 15, 16, 17, 18, 19, 20, 21], hours
  end

  def test_works_out_local_hour_from_a_time_in_any_zone
    same_moment_elsewhere = Time.new(2026, 9, 29, 5, 30, 0, "-07:00")
    hours = @weather.next_hours(local_time: same_moment_elsewhere, hours: 2).map(&:first)

    assert_equal [14, 15], hours
  end

  def test_each_entry_is_hour_temp_condition_and_pop
    hour, temperature, condition, pop = @weather.next_hours(local_time: @afternoon, hours: 1).first

    assert_equal [Integer, Integer, String, Integer], [hour, temperature, condition, pop].map(&:class)
  end

  def stub_weather_codes(codes, from_index: 14)
    forecast = JSON.parse(fixture("open_meteo.json"))
    codes.each_with_index { |code, offset| forecast["hourly"]["weather_code"][from_index + offset] = code }
    stub_request(:get, URL).with(query: hash_including({})).to_return(status: 200, body: forecast.to_json)
  end

  def test_groups_wmo_codes_into_conditions
    stub_weather_codes([0, 2, 3, 45, 53, 65, 73, 97])

    conditions = @weather.next_hours(local_time: @afternoon).map { |row| row[2] }

    assert_equal %w[clear partly cloud fog drizzle rain snow storm], conditions
  end

  def test_every_documented_wmo_code_has_a_condition
    documented = [0, 1, 2, 3, 45, 48, 51, 53, 55, 56, 57, 61, 63, 65, 66, 67, 71, 73, 75, 77, 80, 81, 82, 85, 86, 95, 96, 97, 99]
    known = Weather::CONDITIONS.values.flatten

    assert_empty documented - known
  end

  def test_an_unrecognised_code_becomes_unknown
    stub_weather_codes([42])

    assert_equal "unknown", @weather.next_hours(local_time: @afternoon, hours: 1).first[2]
  end

  def hours_from(hour, minute = 0, count: 8, day: 29)
    local_time = Time.new(2026, 9, day, hour, minute, 0, SVALBARD_OFFSET)

    @weather.next_hours(local_time: local_time, hours: count).map(&:first)
  end

  def test_includes_midnight
    assert_equal [17, 18, 19, 20, 21, 22, 23, 0], hours_from(17)
  end

  def test_skips_the_sleeping_hours_and_carries_on_into_the_next_morning
    assert_equal [21, 22, 23, 0, 8], hours_from(21, 30, count: 5)
  end

  def test_evening_windows_reach_into_tomorrow_morning
    assert_equal [19, 20, 21, 22, 23, 0, 8, 9], hours_from(19)
  end

  def test_after_midnight_the_window_starts_at_eight
    assert_equal [0, 8, 9, 10, 11, 12, 13, 14], hours_from(0, 30)
  end

  def test_in_the_small_hours_the_window_starts_at_eight
    assert_equal [8, 9, 10, 11, 12, 13, 14, 15], hours_from(3)
  end

  def test_a_morning_window_shows_the_working_day
    assert_equal [9, 10, 11, 12, 13, 14, 15, 16], hours_from(9)
  end

  def test_seven_is_still_sleeping
    assert_equal [8], hours_from(7, 59, count: 1)
  end

  def test_one_is_the_first_sleeping_hour
    assert_equal [0], hours_from(0, 59, count: 1)
    assert_equal [8], hours_from(1, count: 1)
  end

  def test_sends_coordinates_and_asks_for_the_hourly_variables
    @weather.next_hours(local_time: @afternoon)

    assert_requested :get, URL, query: hash_including(
      "latitude" => "78.216667",
      "longitude" => "15.633333",
      "hourly" => "temperature_2m,weather_code,precipitation_probability",
      "timezone" => "auto"
    )
  end

  def test_raises_a_clear_error_on_http_failure
    stub_request(:get, URL).with(query: hash_including({})).to_return(status: 503)

    error = assert_raises(Weather::Error) { @weather.next_hours(local_time: @afternoon) }
    assert_match(/503/, error.message)
  end

  def test_raises_a_clear_error_when_the_request_times_out
    stub_request(:get, URL).with(query: hash_including({})).to_timeout

    error = assert_raises(Weather::Error) { @weather.next_hours(local_time: @afternoon) }

    assert_match(/timed out/, error.message)
  end

  def test_raises_naming_the_hour_when_a_value_is_null
    forecast = JSON.parse(fixture("open_meteo.json"))
    forecast["hourly"]["temperature_2m"][15] = nil
    stub_request(:get, URL).with(query: hash_including({})).to_return(status: 200, body: forecast.to_json)

    error = assert_raises(Weather::Error) { @weather.next_hours(local_time: @afternoon) }

    assert_equal "Open-Meteo has no temperature_2m for 2026-09-29T15:00", error.message
  end

  def test_raises_when_a_variable_has_fewer_values_than_hours
    forecast = JSON.parse(fixture("open_meteo.json"))
    forecast["hourly"]["weather_code"] = forecast["hourly"]["weather_code"].first(16)
    stub_request(:get, URL).with(query: hash_including({})).to_return(status: 200, body: forecast.to_json)

    error = assert_raises(Weather::Error) { @weather.next_hours(local_time: @afternoon) }

    assert_equal "Open-Meteo has no weather_code for 2026-09-29T16:00", error.message
  end

  def test_raises_when_the_forecast_does_not_cover_the_window
    far_future = Time.new(2027, 1, 1, 0, 0, 0, "+01:00")

    assert_raises(Weather::Error) { @weather.next_hours(local_time: far_future) }
  end

  def test_raises_when_the_window_runs_past_the_end_of_the_forecast
    last_evening = Time.new(2026, 9, 30, 20, 0, 0, SVALBARD_OFFSET)

    assert_raises(Weather::Error) { @weather.next_hours(local_time: last_evening, hours: 8) }
  end
end
