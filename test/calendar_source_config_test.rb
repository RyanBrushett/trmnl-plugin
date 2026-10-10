require "test_helper"
require "calendar_source"
require "config"
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

  def test_several_calendar_ids_are_passed_through
    Tempfile.create(["service-account", ".json"]) do |file|
      file.write({type: "service_account", project_id: "p", private_key_id: "k", private_key: OpenSSL::PKey::RSA.new(2048).to_pem,
                  client_email: "robot@p.iam.gserviceaccount.com", client_id: "1"}.to_json)
      file.flush
      env = BASE_ENV.merge("GOOGLE_SERVICE_ACCOUNT_KEY_FILE" => file.path, "GOOGLE_CALENDAR_ID" => "me@example.com, me@work.example")

      source = CalendarSource.from_config(Config.from_env(env))

      assert_equal %w[me@example.com me@work.example], source.instance_variable_get(:@calendar_ids)
    end
  end
end
