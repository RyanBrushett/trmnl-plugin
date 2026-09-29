require "date"
require "google/apis/calendar_v3"
require "googleauth"
require "payload"

class CalendarSource
  class Error < StandardError; end

  SCOPE = "https://www.googleapis.com/auth/calendar.events.readonly"
  PAGE_SIZE = 100
  TIMEOUT_SECONDS = 10
  DECLINED = "declined"
  CANCELLED = "cancelled"
  GOOGLE_ERRORS = [Google::Apis::Error, Signet::AuthorizationError].freeze

  def self.from_credentials(client_id:, client_secret:, refresh_token:, calendar_id: "primary")
    service = Google::Apis::CalendarV3::CalendarService.new
    service.client_options.open_timeout_sec = TIMEOUT_SECONDS
    service.client_options.read_timeout_sec = TIMEOUT_SECONDS
    service.authorization = Google::Auth::UserRefreshCredentials.new(
      client_id: client_id, client_secret: client_secret, scope: SCOPE, refresh_token: refresh_token
    )
    new(service: service, calendar_id: calendar_id)
  end

  def initialize(service:, calendar_id: "primary")
    @service = service
    @calendar_id = calendar_id
  end

  # Covers today and tomorrow, because Payload decides which of the two to show.
  def events(local_time:)
    first_day = local_time.to_date
    google_events = fetch(midnight_of(first_day), midnight_of(first_day + 2))

    google_events.reject { |event| cancelled?(event) || declined_by_me?(event) }.map { |event| to_event(event) }
  end

  private

  def fetch(time_min, time_max)
    collected = []
    page_token = nil

    loop do
      page = @service.list_events(
        @calendar_id,
        single_events: true, order_by: "startTime", max_results: PAGE_SIZE,
        time_min: time_min.iso8601, time_max: time_max.iso8601, page_token: page_token
      )
      collected.concat(page.items.to_a)
      page_token = page.next_page_token
      return collected unless page_token
    end
  rescue *GOOGLE_ERRORS => e
    raise Error, "Google Calendar request failed (#{e.class.name.split("::").last}: #{e.message.gsub(/\s+/, " ").strip})"
  end

  def cancelled?(event) = event.status == CANCELLED

  def declined_by_me?(event)
    event.attendees.to_a.any? { |attendee| attendee.self? && attendee.response_status == DECLINED }
  end

  def to_event(event)
    Payload::Event.new(
      title: event.summary,
      starts_at: moment(event.start),
      ends_at: moment(event.end),
      all_day: event.start.date_time.nil?
    )
  end

  def moment(event_time)
    return event_time.date_time.to_time if event_time.date_time

    midnight_of(Date.parse(event_time.date.to_s))
  end

  def midnight_of(date) = Time.local(date.year, date.month, date.day)
end
