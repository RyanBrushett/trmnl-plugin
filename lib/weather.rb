require "json"
require "net/http"
require "uri"

class Weather
  class Error < StandardError; end

  ENDPOINT = URI("https://api.open-meteo.com/v1/forecast")
  HOURLY_VARIABLES = %w[temperature_2m weather_code precipitation_probability].freeze
  TIMEOUT_SECONDS = 10
  SLEEPING_HOURS = (1..7)
  UNKNOWN_CONDITION = "unknown"
  # Grouped from Open-Meteo's WMO weather codes. The template draws one icon per name.
  CONDITIONS = {
    "clear" => [0],
    "partly" => [1, 2],
    "cloud" => [3],
    "fog" => [45, 48],
    "drizzle" => [51, 53, 55, 56, 57],
    "rain" => [61, 63, 65, 66, 67, 80, 81, 82],
    "snow" => [71, 73, 75, 77, 85, 86],
    "storm" => [95, 96, 97, 99]
  }.freeze

  def initialize(lat:, lon:)
    @lat = lat
    @lon = lon
  end

  # Rows are positional, [hour, temp_c, condition, pop_percent], because the
  # TRMNL template reads them by index.
  def next_hours(local_time: Time.now, hours: 8)
    forecast = get
    hourly = forecast.fetch("hourly")
    current_hour = local_hour_label(local_time, forecast.fetch("utc_offset_seconds"))

    labels = hourly.fetch("time")
    first = labels.index(current_hour)
    raise Error, "forecast does not include #{current_hour}" unless first

    waking = (first...labels.size).reject { |index| sleeping?(labels[index]) }
    raise Error, "forecast too short for #{hours} waking hours from #{current_hour}" if waking.size < hours

    waking.first(hours).map { |index| hour_row(hourly, index) }
  end

  private

  def hour_of(label) = label[11, 2].to_i

  def sleeping?(label) = SLEEPING_HOURS.cover?(hour_of(label))

  def hour_row(hourly, index)
    label = hourly["time"][index]
    temperature, code, pop = HOURLY_VARIABLES.map do |variable|
      hourly.fetch(variable, [])[index] || raise(Error, "Open-Meteo has no #{variable} for #{label}")
    end

    [hour_of(label), temperature.round, condition_for(code), pop]
  end

  def condition_for(code)
    CONDITIONS.find { |_name, codes| codes.include?(code) }&.first || UNKNOWN_CONDITION
  end

  def local_hour_label(time, utc_offset_seconds)
    (time.getutc + utc_offset_seconds).strftime("%Y-%m-%dT%H:00")
  end

  def get
    uri = ENDPOINT.dup
    uri.query = URI.encode_www_form(
      latitude: @lat,
      longitude: @lon,
      hourly: HOURLY_VARIABLES.join(","),
      timezone: "auto",
      forecast_days: 2
    )

    response = Net::HTTP.start(
      uri.host, uri.port,
      use_ssl: true, open_timeout: TIMEOUT_SECONDS, read_timeout: TIMEOUT_SECONDS
    ) { |http| http.get(uri.request_uri) }
    raise Error, "Open-Meteo returned HTTP #{response.code}" unless response.is_a?(Net::HTTPSuccess)

    JSON.parse(response.body)
  rescue Net::OpenTimeout, Net::ReadTimeout
    raise Error, "Open-Meteo timed out after #{TIMEOUT_SECONDS} seconds"
  end
end
