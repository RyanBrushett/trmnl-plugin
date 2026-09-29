require "test_helper"
require "payload"

class PayloadTest < Minitest::Test
  E = Payload::Event

  WEATHER = [[14, 13, 3, 6], [15, 13, 3, 1]].freeze

  def setup
    @local_time = at(2026, 9, 28, 14, 30)
  end

  def at(year, month, day, hour, min = 0)
    Time.new(year, month, day, hour, min, 0, SVALBARD_OFFSET)
  end

  def event(title, from, to, **opts)
    E.new(title: title, starts_at: from, ends_at: to, **opts)
  end

  def vars(events: [], weather: WEATHER, local_time: @local_time)
    Payload.build(events: events, weather: weather, local_time: local_time).fetch("merge_variables")
  end

  def test_body_is_wrapped_in_merge_variables
    body = Payload.build(events: [], weather: WEATHER, local_time: @local_time)

    assert_equal ["merge_variables"], body.keys
  end

  def test_mode_is_today_before_the_evening
    assert_equal "today", Payload.mode(at(2026, 9, 28, 19, 59))
    assert_equal "today", Payload.mode(at(2026, 9, 28, 0, 5))
  end

  def test_mode_is_tomorrow_from_eight_pm
    assert_equal "tomorrow", Payload.mode(at(2026, 9, 28, 20, 0))
    assert_equal "tomorrow", Payload.mode(at(2026, 9, 28, 23, 59))
  end

  def test_date_follows_the_mode
    assert_equal "2026-09-28", vars["date"]
    assert_equal "2026-09-29", vars(local_time: at(2026, 9, 28, 21))["date"]
  end

  def test_weather_is_passed_through
    assert_equal WEATHER, vars["weather"]
  end

  def test_events_are_minutes_since_midnight
    e = event("Standup", at(2026, 9, 28, 15, 30), at(2026, 9, 28, 16))

    assert_equal [[930, 960, "Standup"]], vars(events: [e])["events"]
  end

  def test_events_are_sorted_by_start_time
    late = event("Late", at(2026, 9, 28, 17), at(2026, 9, 28, 18))
    early = event("Early", at(2026, 9, 28, 15), at(2026, 9, 28, 16))

    assert_equal %w[Early Late], vars(events: [late, early])["events"].map(&:last)
  end

  def test_work_events_are_shown_as_meeting
    e = event("Q3 budget review", at(2026, 9, 28, 15), at(2026, 9, 28, 16), work: true)

    assert_equal "Meeting", vars(events: [e])["events"].first.last
  end

  def test_realistic_long_titles_are_kept_whole
    titles = ["🧖 Thermal Circuit — Lakeside Sauna & Spa", "🪨 Gravel Grinder — 129km", "🍻 Post-Race Party (on-site)"]
    events = titles.each_with_index.map { |title, i| event(title, at(2026, 9, 28, 15 + i), at(2026, 9, 28, 15 + i, 45)) }

    assert_equal titles, vars(events: events)["events"].map(&:last)
  end

  def test_today_is_always_the_local_date_whichever_day_is_shown
    assert_equal "2026-09-28", vars["today"]
    assert_equal "2026-09-28", vars(local_time: at(2026, 9, 28, 21))["today"]
  end

  def test_long_titles_are_truncated
    e = event("A" * 100, at(2026, 9, 28, 15), at(2026, 9, 28, 16))
    title = vars(events: [e])["events"].first.last

    assert_equal Payload::MAX_TITLE_LENGTH, title.length
    assert title.end_with?("…")
  end

  def test_untitled_events_get_a_placeholder
    missing = event(nil, at(2026, 9, 28, 15), at(2026, 9, 28, 16))
    blank = event("   ", at(2026, 9, 28, 16), at(2026, 9, 28, 17))

    titles = vars(events: [missing, blank])["events"].map(&:last)

    assert_equal [Payload::UNTITLED_EVENT_TITLE] * 2, titles
  end

  def test_times_are_wall_clock_on_the_day_the_clocks_go_forward
    saturday_evening = Time.local(2027, 3, 27, 21)
    brunch = event("Brunch", Time.local(2027, 3, 28, 9), Time.local(2027, 3, 28, 10))

    events = vars(events: [brunch], local_time: saturday_evening)["events"]

    assert_equal [[540, 600, "Brunch"]], events
  end

  def test_times_are_wall_clock_on_the_day_the_clocks_go_back
    saturday_evening = Time.local(2027, 10, 30, 21)
    brunch = event("Brunch", Time.local(2027, 10, 31, 9), Time.local(2027, 10, 31, 10))

    events = vars(events: [brunch], local_time: saturday_evening)["events"]

    assert_equal [[540, 600, "Brunch"]], events
  end

  def test_all_day_events_come_first_with_no_times
    timed = event("Dentist", at(2026, 9, 28, 15), at(2026, 9, 28, 16))
    all_day = event("Thanksgiving", at(2026, 9, 28, 0), at(2026, 9, 29, 0), all_day: true)

    assert_equal [[nil, nil, "Thanksgiving"], [900, 960, "Dentist"]],
      vars(events: [timed, all_day])["events"]
  end

  def test_today_leaves_out_events_that_have_already_ended
    over = event("Breakfast", at(2026, 9, 28, 8), at(2026, 9, 28, 9))
    now_on = event("Lunch", at(2026, 9, 28, 14), at(2026, 9, 28, 15))

    assert_equal ["Lunch"], vars(events: [over, now_on])["events"].map(&:last)
  end

  def test_tomorrow_includes_the_whole_day_and_ignores_today
    today = event("Today thing", at(2026, 9, 28, 21), at(2026, 9, 28, 22))
    early = event("Early run", at(2026, 9, 29, 6), at(2026, 9, 29, 7))

    events = vars(events: [today, early], local_time: at(2026, 9, 28, 21))["events"]

    assert_equal [[360, 420, "Early run"]], events
  end

  def test_events_on_other_days_are_ignored
    next_week = event("Later", at(2026, 10, 5, 10), at(2026, 10, 5, 11))

    assert_empty vars(events: [next_week])["events"]
  end

  def test_events_crossing_midnight_are_clipped_to_the_day
    late = event("Night shift", at(2026, 9, 28, 22), at(2026, 9, 29, 6))

    assert_equal [[1320, 1440, "Night shift"]], vars(events: [late])["events"]
  end

  def test_no_more_than_max_events
    events = Array.new(12) { |i| event("E#{i}", at(2026, 9, 28, 15, i), at(2026, 9, 28, 23)) }

    assert_equal Payload::MAX_EVENTS, vars(events: events)["events"].size
  end

  def test_worst_case_fits_the_trmnl_limit
    events = Array.new(20) do |i|
      event("é" * 100, at(2026, 9, 28, 15, i), at(2026, 9, 28, 23))
    end
    weather = Array.new(8) { |i| [14 + i, -25, 99, 100] }

    body = Payload.build(events: events, weather: weather, local_time: @local_time)

    assert_operator body.to_json.bytesize, :<=, Payload::WEBHOOK_LIMIT_BYTES
    assert_equal weather, body["merge_variables"]["weather"]
  end

  def test_drops_trailing_events_when_over_budget
    events = Array.new(8) { |i| event("é" * 100, at(2026, 9, 28, 15, i), at(2026, 9, 28, 23)) }
    body = Payload.build(events: events, weather: WEATHER, local_time: @local_time, max_bytes: 400)
    kept = body["merge_variables"]["events"]

    assert_operator kept.size, :<, 8
    assert_operator body.to_json.bytesize, :<=, 400
    assert_equal "é" * (Payload::MAX_TITLE_LENGTH - 1) + "…", kept.first.last, "earliest events should survive"
  end
end
