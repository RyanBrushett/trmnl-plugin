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

  def test_mode_is_today_before_the_evening
    assert_equal "today", vars(local_time: at(2026, 9, 28, 19, 59))["mode"]
    assert_equal "today", vars(local_time: at(2026, 9, 28, 0, 5))["mode"]
  end

  def test_mode_is_tomorrow_from_eight_pm
    assert_equal "tomorrow", vars(local_time: at(2026, 9, 28, 20, 0))["mode"]
    assert_equal "tomorrow", vars(local_time: at(2026, 9, 28, 23, 59))["mode"]
  end

  def test_date_follows_the_mode
    assert_equal "2026-09-28", vars["date"]
    assert_equal "2026-09-29", vars(local_time: at(2026, 9, 28, 21))["date"]
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

  def test_all_day_events_are_a_separate_list_of_titles
    timed = event("Dentist", at(2026, 9, 28, 15), at(2026, 9, 28, 16))
    all_day = event("Thanksgiving", at(2026, 9, 28, 0), at(2026, 9, 29, 0), all_day: true)

    result = vars(events: [timed, all_day])

    assert_equal ["Thanksgiving"], result["all_day"]
    assert_equal [[900, 960, "Dentist"]], result["events"]
  end

  def test_no_row_contains_a_null
    all_day = event("Thanksgiving", at(2026, 9, 28, 0), at(2026, 9, 29, 0), all_day: true)

    refute_includes vars(events: [all_day]).to_json, "null"
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

  def test_all_day_events_count_towards_the_maximum_and_come_before_timed_ones
    all_day = Array.new(10) { |i| event("Day #{i}", at(2026, 9, 28, 0), at(2026, 9, 29, 0), all_day: true) }
    timed = event("Dentist", at(2026, 9, 28, 15), at(2026, 9, 28, 16))

    result = vars(events: all_day + [timed])

    assert_equal [Payload::MAX_EVENTS, 0], [result["all_day"].size, result["events"].size]
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
