require "test_helper"
require "config"
require "tmpdir"

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

  # The zone folder also holds text files; an invalid TZ would silently become UTC.
  def test_rejects_text_files_that_live_in_the_zone_folder
    %w[zone.tab tzdata.zi iso3166.tab].each do |name|
      assert_raises(Config::Error, name) { Config.from_env(ENV_VARS.merge("HOME_TIMEZONE" => name)) }
    end
  end

  def test_rejects_names_that_are_not_shaped_like_a_zone
    ["../../etc/hosts", "/etc/hosts", "Arctic//Longyearbyen", "Arctic/Longyearbyen/", "Arctic/../Arctic/Longyearbyen", " "].each do |name|
      assert_raises(Config::Error, name.inspect) { Config.from_env(ENV_VARS.merge("HOME_TIMEZONE" => name)) }
    end
  end

  def test_an_unreadable_zone_file_is_not_a_zone_and_does_not_crash
    skip "root can read any file" if Process.uid.zero?

    Dir.mktmpdir do |dir|
      File.write(File.join(dir, "Locked"), "TZif")
      File.chmod(0o000, File.join(dir, "Locked"))

      refute Config.send(:zone?, "Locked", dir: dir)
    end
  end

  def test_the_zone_check_needs_the_tzif_header_not_just_a_file
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, "Real"), "TZif2 and the rest")
      File.write(File.join(dir, "Text"), "# just notes")

      assert_equal [true, false], [Config.send(:zone?, "Real", dir: dir), Config.send(:zone?, "Text", dir: dir)]
    end
  end

  def test_accepts_real_zones_including_nested_and_signed_ones
    ["America/Argentina/Buenos_Aires", "Etc/GMT+5", "UTC"].each do |name|
      assert_equal name, Config.from_env(ENV_VARS.merge("HOME_TIMEZONE" => name)).timezone
    end
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

  SERVICE_ACCOUNT_VARS = {
    "GOOGLE_SERVICE_ACCOUNT_KEY_FILE" => "/keys/robot.json",
    "GOOGLE_CALENDAR_ID" => "me@example.com"
  }.freeze

  def test_google_settings_are_optional
    config = Config.from_env(ENV_VARS)

    assert_equal [false, nil, nil], [config.google?, config.google_key_file, config.google_calendar_id]
  end

  def test_reads_the_service_account_settings
    config = Config.from_env(ENV_VARS.merge(SERVICE_ACCOUNT_VARS))

    assert_equal [true, "/keys/robot.json", "me@example.com"],
      [config.google?, config.google_key_file, config.google_calendar_id]
  end

  def test_a_half_filled_pair_names_the_missing_calendar_id
    error = assert_raises(Config::Error) { Config.from_env(ENV_VARS.merge(SERVICE_ACCOUNT_VARS.except("GOOGLE_CALENDAR_ID"))) }

    assert_equal "incomplete Google service account settings, missing: GOOGLE_CALENDAR_ID", error.message
  end

  def test_a_half_filled_pair_names_the_missing_key_file
    error = assert_raises(Config::Error) { Config.from_env(ENV_VARS.merge(SERVICE_ACCOUNT_VARS.except("GOOGLE_SERVICE_ACCOUNT_KEY_FILE"))) }

    assert_equal "incomplete Google service account settings, missing: GOOGLE_SERVICE_ACCOUNT_KEY_FILE", error.message
  end

  def test_blank_google_settings_count_as_absent
    config = Config.from_env(ENV_VARS.merge(SERVICE_ACCOUNT_VARS.transform_values { "  " }))

    refute_predicate config, :google?
  end

  def test_leftover_oauth_settings_in_an_env_file_are_ignored
    leftovers = {"GOOGLE_CLIENT_ID" => "id", "GOOGLE_CLIENT_SECRET" => "secret", "GOOGLE_REFRESH_TOKEN" => "token"}

    refute_predicate Config.from_env(ENV_VARS.merge(leftovers)), :google?
  end

  def test_primary_is_not_a_valid_calendar_for_a_service_account
    error = assert_raises(Config::Error) { Config.from_env(ENV_VARS.merge(SERVICE_ACCOUNT_VARS.merge("GOOGLE_CALENDAR_ID" => "Primary"))) }

    assert_match(/must be the calendar's email address/, error.message)
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
