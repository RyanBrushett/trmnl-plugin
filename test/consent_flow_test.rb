require "test_helper"
require "consent_flow"
require "base64"
require "digest"
require "uri"

class ConsentFlowTest < Minitest::Test
  BASE_URL = "http://127.0.0.1:54321"
  TOKEN_URL = "https://oauth2.googleapis.com/token"

  def setup
    @flow = ConsentFlow.new(client_id: "my-client-id", client_secret: "my-client-secret", base_url: BASE_URL)
    @params = URI.decode_www_form(URI(@flow.authorization_url).query).to_h
  end

  def test_sends_the_browser_to_google
    assert_equal "accounts.google.com", URI(@flow.authorization_url).host
  end

  def test_asks_for_read_only_events_and_a_refresh_token
    assert_equal [CalendarSource::SCOPE, "offline"], @params.values_at("scope", "access_type")
  end

  def test_redirects_back_to_the_loopback_receiver
    assert_equal "#{BASE_URL}/oauth2callback", @params["redirect_uri"]
  end

  def test_identifies_the_client_and_carries_the_state
    assert_equal ["my-client-id", @flow.state], @params.values_at("client_id", "state")
  end

  def test_uses_a_fresh_random_state_each_time
    other = ConsentFlow.new(client_id: "id", client_secret: "secret", base_url: BASE_URL)

    refute_equal @flow.state, other.state
  end

  def test_exchanges_the_code_for_a_refresh_token_and_proves_it_with_pkce
    sent = nil
    stub_request(:post, TOKEN_URL).with { |request| sent = URI.decode_www_form(request.body).to_h }.to_return(
      status: 200, headers: {"Content-Type" => "application/json"},
      body: {"access_token" => "access", "refresh_token" => "the-refresh-token", "expires_in" => 3599, "token_type" => "Bearer"}.to_json
    )

    token = @flow.refresh_token_for("the-code")
    challenge = Base64.urlsafe_encode64(Digest::SHA256.digest(sent["code_verifier"]), padding: false)

    assert_equal ["the-refresh-token", "the-code", @params["code_challenge"]], [token, sent["code"], challenge]
  end
end
