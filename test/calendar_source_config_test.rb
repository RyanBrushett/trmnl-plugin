require "test_helper"
require "calendar_source"
require "config"
require "error_payload"
require "openssl"
require "tempfile"

class CalendarSourceConfigTest < Minitest::Test
  BASE_ENV = {
    "HOME_LAT" => "78.2", "HOME_LON" => "15.6", "HOME_TIMEZONE" => "Arctic/Longyearbyen", "TRMNL_WEBHOOK_UUID" => "abc-123"
  }.freeze

  def test_without_google_settings_the_calendar_says_it_is_not_set_up
    source = CalendarSource.from_config(Config.from_env(BASE_ENV))

    error = assert_raises(CalendarSource::Error) { source.events(local_time: Time.now) }

    assert_equal "Google Calendar is not set up (GOOGLE_SERVICE_ACCOUNT_KEY_FILE and GOOGLE_CALENDAR_ID are not set)", error.message
  end

  def test_the_error_screen_names_the_missing_settings
    source = CalendarSource.from_config(Config.from_env(BASE_ENV))
    error = assert_raises(CalendarSource::Error) { source.events(local_time: Time.now) }

    shown = ErrorPayload.build(error, local_time: Time.now).dig("merge_variables", "error")

    assert_includes shown, "GOOGLE_SERVICE_ACCOUNT_KEY_FILE"
  end

  def test_with_google_settings_it_builds_a_real_calendar_using_the_robots_key
    Tempfile.create(["service-account", ".json"]) do |file|
      file.write({type: "service_account", project_id: "p", private_key_id: "k", private_key: OpenSSL::PKey::RSA.new(2048).to_pem,
                  client_email: "robot@p.iam.gserviceaccount.com", client_id: "1"}.to_json)
      file.flush
      env = BASE_ENV.merge("GOOGLE_SERVICE_ACCOUNT_KEY_FILE" => file.path, "GOOGLE_CALENDAR_ID" => "me@example.com")

      source = CalendarSource.from_config(Config.from_env(env))

      assert_instance_of CalendarSource, source
      assert_instance_of Google::Auth::ServiceAccountCredentials, source.instance_variable_get(:@service).authorization
    end
  end

  def test_a_bad_key_file_surfaces_as_a_calendar_error_not_a_crash
    env = BASE_ENV.merge("GOOGLE_SERVICE_ACCOUNT_KEY_FILE" => "/nowhere/robot.json", "GOOGLE_CALENDAR_ID" => "me@example.com")

    assert_raises(CalendarSource::Error) { CalendarSource.from_config(Config.from_env(env)) }
  end
end
