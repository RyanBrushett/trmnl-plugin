require "json"
require "net/http"
require "openssl"
require "uri"

class Webhook
  class Error < StandardError; end

  BASE_URL = "https://trmnl.com/api/custom_plugins"
  TIMEOUT_SECONDS = 10
  NETWORK_ERRORS = [SocketError, SystemCallError, OpenSSL::SSL::SSLError, EOFError].freeze

  def initialize(uuid)
    @uri = URI("#{BASE_URL}/#{uuid}")
  end

  def post(body)
    request = Net::HTTP::Post.new(@uri, "Content-Type" => "application/json")
    request.body = body.to_json

    response = Net::HTTP.start(
      @uri.host, @uri.port,
      use_ssl: true, open_timeout: TIMEOUT_SECONDS, read_timeout: TIMEOUT_SECONDS
    ) { |http| http.request(request) }

    raise Error, "TRMNL webhook returned HTTP #{response.code}" unless response.is_a?(Net::HTTPSuccess)
  rescue Net::OpenTimeout, Net::ReadTimeout
    raise Error, "TRMNL webhook timed out after #{TIMEOUT_SECONDS} seconds"
  rescue *NETWORK_ERRORS => e
    raise Error, "TRMNL webhook unreachable (#{e.class})"
  end
end
