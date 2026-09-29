require "test_helper"
require "config"

class ConfigTest < Minitest::Test
  ENV_VARS = {
    "HOME_LAT" => "78.216667",
    "HOME_LON" => "15.633333",
    "HOME_TIMEZONE" => "Arctic/Longyearbyen",
    "TRMNL_WEBHOOK_UUID" => "abc-123"
  }.freeze

  def test_reads_coordinates_timezone_and_webhook_uuid
    config = Config.from_env(ENV_VARS)

    assert_equal [78.216667, 15.633333, "Arctic/Longyearbyen", "abc-123"],
      [config.lat, config.lon, config.timezone, config.webhook_uuid]
  end

  def test_lists_every_missing_variable_at_once
    error = assert_raises(Config::Error) { Config.from_env({}) }

    assert_equal "missing environment variables: HOME_LAT, HOME_LON, HOME_TIMEZONE, TRMNL_WEBHOOK_UUID", error.message
  end

  def test_blank_values_count_as_missing
    error = assert_raises(Config::Error) { Config.from_env(ENV_VARS.merge("HOME_LAT" => "  ")) }

    assert_match(/HOME_LAT/, error.message)
  end

  def test_the_timezone_has_no_default
    error = assert_raises(Config::Error) { Config.from_env(ENV_VARS.except("HOME_TIMEZONE")) }

    assert_match(/HOME_TIMEZONE/, error.message)
  end

  def test_rejects_a_timezone_that_does_not_exist
    error = assert_raises(Config::Error) { Config.from_env(ENV_VARS.merge("HOME_TIMEZONE" => "Arctic/Longyearbyeen")) }

    assert_equal "unknown HOME_TIMEZONE: Arctic/Longyearbyeen", error.message
  end

  def test_webhook_uuid_is_optional_when_not_required
    config = Config.from_env(ENV_VARS.except("TRMNL_WEBHOOK_UUID"), require_webhook: false)

    assert_nil config.webhook_uuid
  end

  def test_rejects_coordinates_that_are_not_numbers
    error = assert_raises(Config::Error) { Config.from_env(ENV_VARS.merge("HOME_LON" => "east")) }

    assert_equal "HOME_LON is not a number", error.message
  end

  def test_rejects_a_latitude_outside_the_globe
    error = assert_raises(Config::Error) { Config.from_env(ENV_VARS.merge("HOME_LAT" => "91")) }

    assert_equal "HOME_LAT must be between -90 and 90", error.message
  end

  def test_rejects_a_longitude_outside_the_globe
    error = assert_raises(Config::Error) { Config.from_env(ENV_VARS.merge("HOME_LON" => "-181")) }

    assert_equal "HOME_LON must be between -180 and 180", error.message
  end

  def test_accepts_coordinates_at_the_extremes
    config = Config.from_env(ENV_VARS.merge("HOME_LAT" => "-90", "HOME_LON" => "180"))

    assert_equal [-90.0, 180.0], [config.lat, config.lon]
  end

  GOOGLE_VARS = {
    "GOOGLE_CLIENT_ID" => "client-id",
    "GOOGLE_CLIENT_SECRET" => "client-secret",
    "GOOGLE_REFRESH_TOKEN" => "refresh-token"
  }.freeze

  def test_google_settings_are_optional
    config = Config.from_env(ENV_VARS)

    assert_equal [false, nil], [config.google?, config.google_client_id]
  end

  def test_reads_all_three_google_settings
    config = Config.from_env(ENV_VARS.merge(GOOGLE_VARS))

    assert_equal [true, "client-id", "client-secret", "refresh-token"],
      [config.google?, config.google_client_id, config.google_client_secret, config.google_refresh_token]
  end

  def test_a_half_filled_set_of_google_settings_names_what_is_missing
    error = assert_raises(Config::Error) { Config.from_env(ENV_VARS.merge(GOOGLE_VARS.except("GOOGLE_REFRESH_TOKEN"))) }

    assert_equal "incomplete Google settings, missing: GOOGLE_REFRESH_TOKEN", error.message
  end

  def test_blank_google_settings_count_as_absent
    config = Config.from_env(ENV_VARS.merge(GOOGLE_VARS.transform_values { "  " }))

    refute_predicate config, :google?
  end

  def test_rejects_a_webhook_uuid_that_is_not_url_safe
    error = assert_raises(Config::Error) { Config.from_env(ENV_VARS.merge("TRMNL_WEBHOOK_UUID" => "abc def")) }

    assert_match(/TRMNL_WEBHOOK_UUID/, error.message)
  end

  def test_the_uuid_error_does_not_repeat_the_value
    error = assert_raises(Config::Error) { Config.from_env(ENV_VARS.merge("TRMNL_WEBHOOK_UUID" => "abc def")) }

    refute_includes error.message, "abc def"
  end
end
