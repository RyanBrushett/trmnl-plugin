require "date"
require "google/apis/calendar_v3"
require "googleauth"
require "json"
require "openssl"
require "payload"

class CalendarSource
  class Error < StandardError; end

  SCOPE = "https://www.googleapis.com/auth/calendar.events.readonly"
  PAGE_SIZE = 100
  TIMEOUT_SECONDS = 10
  DECLINED = "declined"
  CANCELLED = "cancelled"
  GOOGLE_ERRORS = [Google::Apis::Error, Signet::AuthorizationError].freeze

  KEY_FILE_ERRORS = [SystemCallError, JSON::JSONError, Google::Auth::Error, OpenSSL::OpenSSLError].freeze

  # An unconfigured calendar is an error on the screen, because "Nothing on"
  # would look like a genuinely empty day.
  class Missing
    def events(local_time:)
      raise Error, "Google Calendar is not set up (GOOGLE_SERVICE_ACCOUNT_KEY_FILE and GOOGLE_CALENDAR_ID are not set)"
    end
  end

  def self.from_config(config)
    return Missing.new unless config.google?

    from_service_account(key_file: config.google_key_file, calendar_id: config.google_calendar_id)
  end

  def self.from_service_account(key_file:, calendar_id:)
    path = File.expand_path(key_file)
    credentials = File.open(path) do |key|
      Google::Auth::ServiceAccountCredentials.make_creds(json_key_io: key, scope: SCOPE)
    end

    service = Google::Apis::CalendarV3::CalendarService.new
    service.client_options.open_timeout_sec = TIMEOUT_SECONDS
    service.client_options.read_timeout_sec = TIMEOUT_SECONDS
    service.authorization = credentials
    new(service: service, calendar_id: calendar_id)
  rescue *KEY_FILE_ERRORS => e
    raise Error, "cannot use the service account key #{File.basename(path)} (#{key_error_detail(e)})"
  end

  # The error page is sent to TRMNL, so it must never carry a path or a
  # fragment of the key. Only googleauth's own messages (such as "missing
  # client_email") are safe: they name fields and quote nothing.
  def self.key_error_detail(error)
    name = error.class.name.split("::").last
    error.is_a?(Google::Auth::Error) ? "#{name}: #{error.message}" : name
  end
  private_class_method :key_error_detail

  def initialize(service:, calendar_id:)
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
    event.attendees.to_a.any? { |attendee| attendee.response_status == DECLINED && mine?(attendee) }
  end

  # A service account is not an attendee, so Google's "self" flag never marks
  # the owner. The calendar's own address does.
  def mine?(attendee)
    attendee.email.to_s.casecmp?(@calendar_id)
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
