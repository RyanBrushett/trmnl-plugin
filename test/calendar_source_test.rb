require "test_helper"
require "calendar_source"

class CalendarSourceTest < Minitest::Test
  CALENDAR_ID = "me@example.com"
  URL = "https://www.googleapis.com/calendar/v3/calendars/#{CALENDAR_ID}/events"
  LOCAL_TIME = Time.new(2026, 9, 29, 14, 30, 0, SVALBARD_OFFSET)

  def setup
    @source = CalendarSource.new(service: Google::Apis::CalendarV3::CalendarService.new, calendar_ids: [CALENDAR_ID])
  end

  def timed(summary, from, to, **extra)
    {"status" => "confirmed", "summary" => summary,
     "start" => {"dateTime" => from}, "end" => {"dateTime" => to}}.merge(extra)
  end

  def all_day(summary, from, to)
    {"status" => "confirmed", "summary" => summary, "start" => {"date" => from}, "end" => {"date" => to}}
  end

  def stub_events(items, **response)
    stub_request(:get, URL).with(query: hash_including({})).to_return(
      status: 200, body: {"items" => items}.merge(response).to_json, headers: {"Content-Type" => "application/json"}
    )
  end

  def fetched(items)
    stub_events(items)
    @source.events(local_time: LOCAL_TIME)
  end

  def test_maps_a_timed_event
    event = fetched([timed("Dentist", "2026-09-29T15:00:00+02:00", "2026-09-29T16:00:00+02:00")]).first

    assert_equal ["Dentist", Time.new(2026, 9, 29, 15, 0, 0, SVALBARD_OFFSET), Time.new(2026, 9, 29, 16, 0, 0, SVALBARD_OFFSET), false],
      [event.title, event.starts_at, event.ends_at, event.all_day]
  end

  def test_maps_an_all_day_event_to_local_midnights_with_an_exclusive_end
    event = fetched([all_day("Long weekend", "2026-09-29", "2026-09-30")]).first

    assert_equal [true, Time.local(2026, 9, 29), Time.local(2026, 9, 30)], [event.all_day, event.starts_at, event.ends_at]
  end

  def test_all_day_events_end_before_the_next_day_starts_in_the_payload
    stub_events([all_day("Long weekend", "2026-09-29", "2026-09-30")])
    events = @source.events(local_time: Time.new(2026, 9, 29, 21, 0, 0, SVALBARD_OFFSET))

    body = Payload.build(events: events, weather: [], local_time: Time.new(2026, 9, 29, 21, 0, 0, SVALBARD_OFFSET))

    assert_empty body.dig("merge_variables", "all_day")
  end

  def test_an_event_with_no_title_is_called_busy
    event = fetched([{"status" => "confirmed", "start" => {"dateTime" => "2026-09-29T15:00:00+02:00"}, "end" => {"dateTime" => "2026-09-29T16:00:00+02:00"}}]).first

    assert_equal "Busy", event.title
  end

  def test_a_blank_title_is_called_busy
    assert_equal ["Busy"], fetched([timed("  ", "2026-09-29T15:00:00+02:00", "2026-09-29T16:00:00+02:00")]).map(&:title)
  end

  def test_hides_events_i_have_declined
    declined = timed("Skipped", "2026-09-29T15:00:00+02:00", "2026-09-29T16:00:00+02:00",
      "attendees" => [{"email" => CALENDAR_ID, "responseStatus" => "declined"}])

    assert_empty fetched([declined])
  end

  def test_keeps_events_someone_else_declined
    others = timed("Team lunch", "2026-09-29T12:00:00+02:00", "2026-09-29T13:00:00+02:00",
      "attendees" => [{"email" => CALENDAR_ID, "responseStatus" => "accepted"},
        {"email" => "them@example.com", "responseStatus" => "declined"}])

    assert_equal ["Team lunch"], fetched([others]).map(&:title)
  end

  def test_keeps_tentative_and_not_yet_answered_events
    statuses = %w[tentative needsAction accepted].map do |response|
      timed(response, "2026-09-29T15:00:00+02:00", "2026-09-29T16:00:00+02:00",
        "attendees" => [{"email" => CALENDAR_ID, "responseStatus" => response}])
    end

    assert_equal %w[tentative needsAction accepted], fetched(statuses).map(&:title)
  end

  def test_hides_cancelled_events
    cancelled = timed("Gone", "2026-09-29T15:00:00+02:00", "2026-09-29T16:00:00+02:00", "status" => "cancelled")

    assert_empty fetched([cancelled])
  end

  def test_asks_google_to_expand_recurring_events_for_today_and_tomorrow
    fetched([])

    assert_requested :get, URL, query: hash_including(
      "singleEvents" => "true", "orderBy" => "startTime",
      "timeMin" => "2026-09-29T00:00:00+02:00", "timeMax" => "2026-10-01T00:00:00+02:00"
    )
  end

  def test_follows_pages_until_there_are_no_more
    stub_events([timed("First", "2026-09-29T09:00:00+02:00", "2026-09-29T10:00:00+02:00")], "nextPageToken" => "page-2")
    stub_request(:get, URL).with(query: hash_including("pageToken" => "page-2")).to_return(
      status: 200, headers: {"Content-Type" => "application/json"},
      body: {"items" => [timed("Second", "2026-09-29T11:00:00+02:00", "2026-09-29T12:00:00+02:00")]}.to_json
    )

    assert_equal %w[First Second], @source.events(local_time: LOCAL_TIME).map(&:title)
  end

  def test_an_empty_calendar_gives_no_events
    stub_request(:get, URL).with(query: hash_including({})).to_return(
      status: 200, body: "{}", headers: {"Content-Type" => "application/json"}
    )

    assert_empty @source.events(local_time: LOCAL_TIME)
  end

  def test_an_expired_login_is_a_clear_error
    stub_request(:get, URL).with(query: hash_including({})).to_return(status: 401, body: '{"error":{"message":"Invalid Credentials"}}', headers: {"Content-Type" => "application/json"})

    error = assert_raises(CalendarSource::Error) { @source.events(local_time: LOCAL_TIME) }

    assert_match(/Google Calendar request failed \(AuthorizationError/, error.message)
  end

  def test_error_messages_are_a_single_line_so_they_sit_neatly_on_the_error_screen
    body = "{\n  \"error\": {\n    \"message\": \"Invalid Credentials\"\n  }\n}"
    stub_request(:get, URL).with(query: hash_including({})).to_return(status: 401, body: body, headers: {"Content-Type" => "application/json"})

    error = assert_raises(CalendarSource::Error) { @source.events(local_time: LOCAL_TIME) }

    refute_match(/\s{2}|\n/, error.message)
  end

  def test_a_timeout_is_a_clear_error
    stub_request(:get, URL).with(query: hash_including({})).to_timeout

    error = assert_raises(CalendarSource::Error) { @source.events(local_time: LOCAL_TIME) }

    assert_match(/TransmissionError/, error.message)
  end

  class TwoCalendars < Minitest::Test
    MINE = "me@example.com"
    WORK = "me@work.example"
    LOCAL_TIME = Time.new(2026, 9, 29, 14, 30, 0, SVALBARD_OFFSET)
    JSON_HEADERS = {"Content-Type" => "application/json"}.freeze

    def setup
      @source = CalendarSource.new(service: Google::Apis::CalendarV3::CalendarService.new, calendar_ids: [MINE, WORK])
    end

    def url(calendar_id) = "https://www.googleapis.com/calendar/v3/calendars/#{calendar_id}/events"

    def stub_calendar(calendar_id, items, status: 200)
      stub_request(:get, url(calendar_id)).with(query: hash_including({})).to_return(
        status: status, body: {"items" => items}.to_json, headers: JSON_HEADERS
      )
    end

    def timed(summary, hour, **extra)
      {"status" => "confirmed", "summary" => summary,
       "start" => {"dateTime" => "2026-09-29T#{hour}:00:00+02:00"}, "end" => {"dateTime" => "2026-09-29T#{hour + 1}:00:00+02:00"}}.merge(extra)
    end

    def test_combines_events_from_every_calendar_in_start_order
      stub_calendar(MINE, [timed("Dentist", 17)])
      stub_calendar(WORK, [timed("Standup", 15)])

      assert_equal %w[Standup Dentist], @source.events(local_time: LOCAL_TIME).map(&:title)
    end

    def test_a_declined_event_is_judged_against_the_calendar_it_came_from
      declined_by_work = timed("Skipped", 15, "attendees" => [{"email" => WORK, "responseStatus" => "declined"}])
      declined_by_work_on_mine = timed("Kept", 16, "attendees" => [{"email" => WORK, "responseStatus" => "declined"}])
      stub_calendar(WORK, [declined_by_work])
      stub_calendar(MINE, [declined_by_work_on_mine])

      assert_equal ["Kept"], @source.events(local_time: LOCAL_TIME).map(&:title)
    end

    def test_one_calendar_failing_fails_the_whole_read
      stub_calendar(MINE, [timed("Dentist", 17)])
      stub_calendar(WORK, [], status: 404)

      assert_raises(CalendarSource::Error) { @source.events(local_time: LOCAL_TIME) }
    end
  end
end
