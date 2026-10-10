require "test_helper"
require "base64"
require "calendar_source"
require "openssl"
require "tempfile"

class CalendarSourceServiceAccountTest < Minitest::Test
  EVENTS_URL = %r{\Ahttps://www\.googleapis\.com/calendar/v3/calendars/[^/]+/events}
  TOKEN_URL = Google::Auth::ServiceAccountCredentials::TOKEN_CRED_URI
  ROBOT = "robot@example-project.iam.gserviceaccount.com"
  CALENDAR = "me@example.com"
  KEY = OpenSSL::PKey::RSA.new(2048)
  LOCAL_TIME = Time.new(2026, 9, 29, 14, 30, 0, SVALBARD_OFFSET)
  JSON_HEADERS = {"Content-Type" => "application/json"}.freeze

  def setup
    @key_file = Tempfile.new(["service-account", ".json"])
    @key_file.write(key_json.to_json)
    @key_file.flush
    @token_request = nil
    stub_token(access_token: "robot-token")
  end

  def teardown
    @key_file.close!
    super
  end

  def key_json
    {type: "service_account", project_id: "example-project", private_key_id: "key-1", private_key: KEY.to_pem,
     client_email: ROBOT, client_id: "1", token_uri: TOKEN_URL}
  end

  def stub_token(access_token:)
    stub_request(:post, TOKEN_URL).with { |request| @token_request = URI.decode_www_form(request.body).to_h }.to_return(
      status: 200, headers: JSON_HEADERS, body: {access_token: access_token, token_type: "Bearer", expires_in: 3599}.to_json
    )
  end

  def stub_events(items)
    stub_request(:get, EVENTS_URL).with(query: hash_including({})).to_return(
      status: 200, headers: JSON_HEADERS, body: {"items" => items}.to_json
    )
  end

  def timed(summary, **extra)
    {"status" => "confirmed", "summary" => summary,
     "start" => {"dateTime" => "2026-09-29T15:00:00+02:00"}, "end" => {"dateTime" => "2026-09-29T16:00:00+02:00"}}.merge(extra)
  end

  def source(calendar_id: CALENDAR)
    CalendarSource.from_service_account(key_file: @key_file.path, calendar_ids: [calendar_id])
  end

  def test_reads_events_using_the_token_the_key_earns
    stub_events([timed("Dentist")])

    titles = source.events(local_time: LOCAL_TIME).map(&:title)

    assert_equal ["Dentist"], titles
    assert_requested :get, EVENTS_URL, headers: {"Authorization" => "Bearer robot-token"}
  end

  def test_asks_for_the_named_calendar_and_not_primary
    stub_events([])
    source.events(local_time: LOCAL_TIME)

    assert_requested :get, %r{/calendars/me(@|%40)example\.com/events}
  end

  def test_asks_for_read_only_access_to_events
    stub_events([])
    source.events(local_time: LOCAL_TIME)
    claims = JSON.parse(Base64.urlsafe_decode64(@token_request["assertion"].split(".")[1]))

    assert_equal "https://www.googleapis.com/auth/calendar.events.readonly", claims["scope"]
  end

  def test_hides_events_the_owner_declined_even_though_the_robot_is_not_an_attendee
    declined = timed("Skipped", "attendees" => [{"email" => "ME@Example.com", "responseStatus" => "declined"}])
    stub_events([declined])

    assert_empty source.events(local_time: LOCAL_TIME)
  end

  def test_a_rejected_token_request_is_a_clear_error
    stub_request(:post, TOKEN_URL).to_return(status: 400, headers: JSON_HEADERS, body: '{"error":"invalid_grant"}')
    stub_events([])

    error = assert_raises(CalendarSource::Error) { source.events(local_time: LOCAL_TIME) }

    assert_match(/Google Calendar request failed \(AuthorizationError/, error.message)
  end

  def test_a_missing_key_file_is_a_clear_error_that_does_not_leak_the_path
    error = assert_raises(CalendarSource::Error) do
      CalendarSource.from_service_account(key_file: "/some/private/dir/robot.json", calendar_ids: [CALENDAR])
    end

    assert_equal "cannot use the service account key robot.json (ENOENT)", error.message
  end

  def test_a_key_file_that_is_not_json_is_a_clear_error_that_never_quotes_its_contents
    File.write(@key_file.path, "{\"private_key\": THIS_IS_A_FAKE_PRIVATE_KEY}")

    error = assert_raises(CalendarSource::Error) { source }

    assert_equal "cannot use the service account key #{File.basename(@key_file.path)} (ParserError)", error.message
  end

  def test_a_garbage_private_key_is_a_clear_error_without_quoting_it
    File.write(@key_file.path, key_json.merge(private_key: "nonsense-key-material").to_json)

    error = assert_raises(CalendarSource::Error) { source }

    refute_match(/nonsense-key-material/, error.message)
  end

  def test_a_client_secret_file_downloaded_by_mistake_says_what_is_missing
    File.write(@key_file.path, {installed: {client_id: "x", client_secret: "y"}}.to_json)

    error = assert_raises(CalendarSource::Error) { source }

    assert_match(/missing client_email/, error.message)
  end

  def test_the_service_uses_the_robots_credentials_and_has_timeouts
    service = source.instance_variable_get(:@service)

    assert_equal [Google::Auth::ServiceAccountCredentials, CalendarSource::TIMEOUT_SECONDS, CalendarSource::TIMEOUT_SECONDS],
      [service.authorization.class, service.client_options.open_timeout_sec, service.client_options.read_timeout_sec]
  end
end
