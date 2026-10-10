require "test_helper"
require "error_payload"
require "payload"
require "template"
require "weather"

class TemplateTest < Minitest::Test
  AFTERNOON = Time.new(2026, 9, 29, 14, 30, 0, SVALBARD_OFFSET)
  EVENING = Time.new(2026, 9, 29, 21, 0, 0, SVALBARD_OFFSET)
  DAYTIME_WEATHER = [[14, 13, "clear", 6], [15, 12, "cloud", 10]].freeze

  def render(events: [], weather: DAYTIME_WEATHER, local_time: AFTERNOON)
    body = Payload.build(events: events, weather: weather, local_time: local_time)
    Template.new.render(body)
  end

  def event(title, from, to, **options)
    Payload::Event.new(title: title, starts_at: from, ends_at: to, **options)
  end

  def at(hour, minute = 0)
    Time.new(2026, 9, 29, hour, minute, 0, SVALBARD_OFFSET)
  end

  def test_the_daytime_header_says_events_today_without_repeating_the_date
    html = render

    assert_includes html, "Events Today"
    refute_includes html, "Events Today ("
  end

  def test_the_evening_header_names_tomorrows_date
    assert_includes render(local_time: EVENING), "Events Tomorrow (Wed 30 Sept)"
  end

  def test_the_right_hand_date_is_always_today
    assert_includes render, "Tue 29 Sept"
    assert_includes render(local_time: EVENING), "Tue 29 Sept"
  end

  def test_keeps_the_other_months_abbreviated_as_usual
    october = Time.new(2026, 10, 5, 14, 30, 0, SVALBARD_OFFSET)

    assert_includes render(local_time: october), "Mon 5 Oct"
  end

  def test_long_titles_with_emoji_and_dashes_are_kept_whole
    title = "🧖 Thermal Circuit — Lakeside Sauna & Spa"
    html = render(events: [event(title, at(15), at(16))])

    assert_includes html, "🧖 Thermal Circuit — Lakeside Sauna &amp; Spa"
  end

  def test_event_titles_are_escaped_so_an_invite_cannot_inject_markup
    html = render(events: [event("<script>alert(1)</script>", at(15), at(16))])

    refute_includes html, "<script>alert"
    assert_includes html, "&lt;script&gt;"
  end

  def test_error_text_is_escaped_too
    error = RuntimeError.new("<img src=x onerror=alert(1)>")
    html = Template.new.render(ErrorPayload.build(error, local_time: AFTERNOON))

    refute_includes html, "<img src=x"
  end

  def test_shows_event_times_and_titles
    html = render(events: [event("Dentist", at(15), at(16))])

    assert_includes html, "15:00–16:00"
    assert_includes html, "Dentist"
  end

  def test_pads_single_digit_hours_and_minutes
    html = render(events: [event("Coffee", at(15, 5), at(15, 50))])

    assert_includes html, "15:05–15:50"
  end

  def test_an_event_ending_at_midnight_ends_at_24_00
    html = render(events: [event("Late film", at(22), at(23, 59) + 60)])

    assert_includes html, "22:00–24:00"
  end

  def test_all_day_events_say_so
    html = render(events: [event("Long weekend", at(0), at(23, 59), all_day: true)])

    assert_includes html, "All day"
  end

  def test_a_day_with_only_all_day_events_is_not_empty
    html = render(events: [event("Long weekend", at(0), at(23, 59), all_day: true)])

    refute_includes html, "Nothing on"
  end

  def test_says_when_there_is_nothing_on
    assert_includes render(events: []), "Nothing on"
  end

  def test_does_not_say_nothing_on_when_there_are_events
    html = render(events: [event("Dentist", at(15), at(16))])

    refute_includes html, "Nothing on"
  end

  def test_shows_weather_hours_temperatures_and_chances_of_rain
    html = render(weather: [[9, -12, "snow", 70]])

    assert_includes html, ">09:00<"
    assert_includes html, "-12°"
    assert_includes html, "PoP: 70%"
  end

  def test_draws_one_icon_per_hour
    conditions = Weather::CONDITIONS.keys + [Weather::UNKNOWN_CONDITION]
    weather = conditions.each_with_index.map { |condition, i| [9 + i, 10, condition, 0] }

    assert_equal conditions.size, render(weather: weather).scan("<svg").size
  end

  def test_marks_the_jump_from_midnight_to_the_next_morning
    weather = [[22, 8, "cloud", 0], [23, 8, "cloud", 0], [0, 7, "clear", 0], [8, 6, "fog", 5]]

    assert_equal 1, render(weather: weather).scan("border-left").size
  end

  def test_does_not_mark_consecutive_hours_including_the_wrap_past_midnight
    weather = [[22, 8, "cloud", 0], [23, 8, "cloud", 0], [0, 7, "clear", 0], [1, 7, "clear", 0]]

    assert_equal 0, render(weather: weather).scan("border-left").size
  end

  def test_the_error_screen_says_what_went_wrong_and_where
    error = Weather::Error.new("Open-Meteo returned HTTP 503")
    html = Template.new.render(ErrorPayload.build(error, local_time: AFTERNOON))

    assert_includes html, "Update failed"
    assert_includes html, "Weather::Error: Open-Meteo returned HTTP 503"
    assert_includes html, "2026-09-29 14:30"
  end

  def test_the_error_screen_has_no_schedule_or_weather
    html = Template.new.render(ErrorPayload.build(RuntimeError.new("boom"), local_time: AFTERNOON))

    refute_includes html, "<svg"
  end
end
