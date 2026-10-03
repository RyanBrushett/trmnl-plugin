class Config < Data.define(:lat, :lon, :webhook_uuid, :timezone, :google_key_file, :google_calendar_id)
  class Error < StandardError; end

  ZONEINFO_DIR = "/usr/share/zoneinfo"
  ZONE_NAME = %r{\A[A-Za-z0-9_+-]+(?:/[A-Za-z0-9_+-]+)*\z}
  ZONE_FILE_MAGIC = "TZif"
  URL_SAFE_ID = /\A[A-Za-z0-9_-]+\z/
  GOOGLE_SETTINGS = {
    google_key_file: "GOOGLE_SERVICE_ACCOUNT_KEY_FILE",
    google_calendar_id: "GOOGLE_CALENDAR_ID"
  }.freeze

  def self.from_env(env, require_webhook: true)
    required = %w[HOME_LAT HOME_LON HOME_TIMEZONE]
    required << "TRMNL_WEBHOOK_UUID" if require_webhook
    missing = required.select { |name| env[name].to_s.strip.empty? }
    raise Error, "missing environment variables: #{missing.join(", ")}" if missing.any?

    new(
      lat: coordinate(env, "HOME_LAT", limit: 90),
      lon: coordinate(env, "HOME_LON", limit: 180),
      webhook_uuid: webhook_uuid(env),
      timezone: timezone(env),
      **google_settings(env)
    )
  end

  def google? = !google_key_file.nil?

  def self.coordinate(env, name, limit:)
    value = Float(env[name])
    raise Error, "#{name} must be between -#{limit} and #{limit}" unless value.abs <= limit

    value
  rescue ArgumentError
    raise Error, "#{name} is not a number"
  end
  private_class_method :coordinate

  def self.timezone(env)
    name = env["HOME_TIMEZONE"]
    raise Error, "unknown HOME_TIMEZONE: #{name}" unless zone?(name)

    name
  end
  private_class_method :timezone

  # The zone folder also holds text files such as zone.tab, and an invalid
  # TZ silently becomes UTC, so check the name's shape and the file's header.
  def self.zone?(name, dir: ZONEINFO_DIR)
    return false unless ZONE_NAME.match?(name)

    path = File.join(dir, name)
    File.file?(path) && File.binread(path, ZONE_FILE_MAGIC.bytesize) == ZONE_FILE_MAGIC
  rescue SystemCallError
    false
  end
  private_class_method :zone?

  # The message never repeats the value, because it is a secret.
  def self.webhook_uuid(env)
    uuid = env["TRMNL_WEBHOOK_UUID"]
    raise Error, "TRMNL_WEBHOOK_UUID contains characters that are not valid in a URL" if uuid && !URL_SAFE_ID.match?(uuid)

    uuid
  end
  private_class_method :webhook_uuid

  # Optional, but both or neither: a half-filled pair is a mistake worth naming.
  def self.google_settings(env)
    values = GOOGLE_SETTINGS.transform_values { |name| env[name].to_s.strip.then { |value| value.empty? ? nil : value } }
    return values if values.values.none?

    missing = GOOGLE_SETTINGS.select { |key, _| values[key].nil? }.values
    raise Error, "incomplete Google service account settings, missing: #{missing.join(", ")}" if missing.any?

    if values[:google_calendar_id].casecmp?("primary")
      raise Error, "GOOGLE_CALENDAR_ID must be the calendar's email address, because for a service account \"primary\" is its own empty calendar"
    end

    values
  end
  private_class_method :google_settings
end
