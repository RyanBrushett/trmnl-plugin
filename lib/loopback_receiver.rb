require "socket"
require "uri"

# Catches Google's redirect back to this machine during the one-off consent.
class LoopbackReceiver
  class Error < StandardError; end

  DEFAULT_TIMEOUT_SECONDS = 300
  PAGE = "<!DOCTYPE html><html><body><p>Done. You can close this tab and go back to your terminal.</p></body></html>"

  def initialize
    @server = TCPServer.new("127.0.0.1", 0)
  end

  def base_url = "http://127.0.0.1:#{@server.addr[1]}"

  def close = @server.close

  # Returns the authorisation code from the first redirect that carries one.
  def wait_for_code(expected_state:, timeout: DEFAULT_TIMEOUT_SECONDS)
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout

    loop do
      client = accept_before(deadline)
      params = read_params(client)
      reply(client, params)
      next unless params.key?("code") || params.key?("error")

      raise Error, "Google returned an error: #{params["error"]}" if params.key?("error")
      raise Error, "the state in Google's reply did not match, so it was ignored" unless params["state"] == expected_state

      return params.fetch("code")
    end
  end

  private

  def accept_before(deadline)
    remaining = deadline - Process.clock_gettime(Process::CLOCK_MONOTONIC)
    raise Error, "timed out waiting for Google" unless remaining.positive? && IO.select([@server], nil, nil, remaining)

    @server.accept
  end

  def read_params(client)
    request_line = client.gets.to_s
    nil while (line = client.gets) && line != "\r\n"
    query = URI.parse(request_line.split[1].to_s).query
    query ? URI.decode_www_form(query).to_h : {}
  rescue URI::InvalidURIError
    {}
  end

  def reply(client, params)
    status, body = (params.key?("code") || params.key?("error")) ? ["200 OK", PAGE] : ["404 Not Found", nil]
    client.write("HTTP/1.1 #{status}\r\nContent-Type: text/html\r\nConnection: close\r\n\r\n#{body}")
  ensure
    client.close
  end
end
