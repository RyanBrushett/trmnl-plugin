class Config < Data.define(:lat, :lon, :webhook_uuid, :timezone, :google_client_id, :google_client_secret, :google_refresh_token)
  class Error < StandardError; end

  ZONEINFO_DIR = "/usr/share/zoneinfo"
  URL_SAFE_ID = /\A[A-Za-z0-9_-]+\z/
  GOOGLE_SETTINGS = {
    google_client_id: "GOOGLE_CLIENT_ID",
    google_client_secret: "GOOGLE_CLIENT_SECRET",
    google_refresh_token: "GOOGLE_REFRESH_TOKEN"
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

  def google?
    !google_client_id.nil?
  end

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
    raise Error, "unknown HOME_TIMEZONE: #{name}" unless File.file?(File.join(ZONEINFO_DIR, name))

    name
  end
  private_class_method :timezone

  # The message never repeats the value, because it is a secret.
  def self.webhook_uuid(env)
    uuid = env["TRMNL_WEBHOOK_UUID"]
    raise Error, "TRMNL_WEBHOOK_UUID contains characters that are not valid in a URL" if uuid && !URL_SAFE_ID.match?(uuid)

    uuid
  end
  private_class_method :webhook_uuid

  # Optional, but all three or none: a half-filled set is a mistake worth naming.
  def self.google_settings(env)
    values = GOOGLE_SETTINGS.transform_values { |name| env[name].to_s.strip.then { |value| value.empty? ? nil : value } }
    return values if values.values.none?

    missing = GOOGLE_SETTINGS.select { |key, _| values[key].nil? }.values
    raise Error, "incomplete Google settings, missing: #{missing.join(", ")}" if missing.any?

    values
  end
  private_class_method :google_settings
end
