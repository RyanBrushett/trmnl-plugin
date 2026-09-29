require "test_helper"
require "webhook"

class WebhookTest < Minitest::Test
  UUID = "0b5a3c2e-secret-uuid"
  URL = "https://trmnl.com/api/custom_plugins/#{UUID}"
  BODY = {"merge_variables" => {"mode" => "today"}}.freeze

  def test_posts_the_body_as_json
    stub = stub_request(:post, URL)
      .with(body: BODY.to_json, headers: {"Content-Type" => "application/json"})
      .to_return(status: 200)

    Webhook.new(UUID).post(BODY)

    assert_requested stub
  end

  def test_raises_on_a_rate_limit_response
    stub_request(:post, URL).to_return(status: 429)

    error = assert_raises(Webhook::Error) { Webhook.new(UUID).post(BODY) }

    assert_match(/429/, error.message)
  end

  def test_raises_on_a_server_error
    stub_request(:post, URL).to_return(status: 500)

    assert_raises(Webhook::Error) { Webhook.new(UUID).post(BODY) }
  end

  def test_raises_a_clear_error_when_the_request_times_out
    stub_request(:post, URL).to_timeout

    error = assert_raises(Webhook::Error) { Webhook.new(UUID).post(BODY) }

    assert_match(/timed out/, error.message)
  end

  def test_raises_a_clear_error_when_the_network_is_down
    stub_request(:post, URL).to_raise(SocketError)

    error = assert_raises(Webhook::Error) { Webhook.new(UUID).post(BODY) }

    assert_equal "TRMNL webhook unreachable (SocketError)", error.message
  end

  def test_raises_a_clear_error_when_the_connection_is_refused
    stub_request(:post, URL).to_raise(Errno::ECONNREFUSED)

    error = assert_raises(Webhook::Error) { Webhook.new(UUID).post(BODY) }

    assert_match(/unreachable/, error.message)
  end

  def test_error_messages_do_not_contain_the_uuid
    stub_request(:post, URL).to_return(status: 404)

    error = assert_raises(Webhook::Error) { Webhook.new(UUID).post(BODY) }

    refute_includes error.message, UUID
  end
end
